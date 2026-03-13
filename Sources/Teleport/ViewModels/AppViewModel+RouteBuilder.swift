import Foundation
import MapKit

fileprivate struct SuggestedNavigationAlternative: Sendable {
    let waypoints: [RouteWaypoint]
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval?
}

fileprivate enum NavigationRouteSuggestionError: LocalizedError {
    case noRouteFound
    case invalidRouteGeometry

    var errorDescription: String? {
        switch self {
        case .noRouteFound:
            return "Apple Maps did not return a route for those points."
        case .invalidRouteGeometry:
            return "Apple Maps returned an empty route geometry."
        }
    }
}

fileprivate struct NavigationRouteSuggestionService {
    func suggestedAlternatives(
        from start: LocationCoordinate,
        to end: LocationCoordinate,
        transport: RouteBuilderNavigationTransport,
        requestsAlternates: Bool
    ) async throws -> [SuggestedNavigationAlternative] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.clLocationCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.clLocationCoordinate))
        request.transportType = transport.directionsTransportType
        request.requestsAlternateRoutes = requestsAlternates

        let response = try await MKDirections(request: request).calculate()
        guard !response.routes.isEmpty else {
            throw NavigationRouteSuggestionError.noRouteFound
        }

        let alternatives = try response.routes.map { route in
            let coordinates = route.polyline.coordinates.map(LocationCoordinate.init)
            guard coordinates.count > 1 else {
                throw NavigationRouteSuggestionError.invalidRouteGeometry
            }

            let segmentDistances = zip(coordinates, coordinates.dropFirst()).map { $0.distance(to: $1) }
            let totalDistance = segmentDistances.reduce(0, +)

            var waypoints: [RouteWaypoint] = []
            waypoints.reserveCapacity(coordinates.count - 1)

            for (index, coordinate) in coordinates.dropFirst().enumerated() {
                let expectedTravelTime: TimeInterval?
                if totalDistance > 0, route.expectedTravelTime > 0 {
                    expectedTravelTime = route.expectedTravelTime * (segmentDistances[index] / totalDistance)
                } else {
                    expectedTravelTime = nil
                }

                waypoints.append(
                    RouteWaypoint(
                        coordinate: ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: coordinate),
                        expectedTravelTime: expectedTravelTime
                    )
                )
            }

            return SuggestedNavigationAlternative(
                waypoints: waypoints,
                distanceMeters: route.distance,
                expectedTravelTime: route.expectedTravelTime > 0 ? route.expectedTravelTime : nil
            )
        }

        return alternatives
    }
}

extension RouteBuilderNavigationTransport {
    fileprivate var directionsTransportType: MKDirectionsTransportType {
        switch self {
        case .driving:
            return .automobile
        case .cycling:
            return .cycling
        case .walking:
            return .walking
        }
    }
}

extension MKPolyline {
    fileprivate var coordinates: [CLLocationCoordinate2D] {
        guard pointCount > 0 else {
            return []
        }

        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

extension LocationCoordinate {
    fileprivate init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    fileprivate var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension AppViewModel {
    func clearRouteBuilderDraft(keepingBuilderActive: Bool = false) {
        routeBuilderNavigationTask?.cancel()
        routeBuilderNavigationTask = nil
        isRouteBuilderResolvingNavigation = false
        routeBuilderStops = []
        draftRouteWaypoints = []
        routeBuilderLatestSegmentAlternatives = []
        routeBuilderSelectedAlternativeIndex = 0
        routeBuilderLatestSegmentPrefixWaypointCount = 0
        isRouteBuilderActive = keepingBuilderActive
    }

    func startRouteBuilder() {
        stopRoutePlayback(resetToReadyState: false)
        loadedRoute = nil
        clearRouteBuilderDraft(keepingBuilderActive: true)
        routePlaybackState = .idle
        statusMessage = .localized(TeleportStrings.routeBuilderStarted)
    }

    func handleRouteBuilderTap(_ displayedCoordinate: LocationCoordinate) {
        guard isRouteBuilderActive else {
            return
        }

        if isRouteBuilderResolvingNavigation {
            statusMessage = .localized(TeleportStrings.routeBuilderNavigationInProgress)
            return
        }

        switch routeBuilderMode {
        case .straightLine:
            appendStraightLineStop(displayedCoordinate)
        case .navigation:
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await appendNavigationStop(displayedCoordinate)
            }
            routeBuilderNavigationTask = task
        }
    }

    func setRouteBuilderMode(_ mode: RouteBuilderMode) {
        guard routeBuilderMode != mode else {
            return
        }

        routeBuilderNavigationTask?.cancel()
        routeBuilderNavigationTask = nil
        isRouteBuilderResolvingNavigation = false
        routeBuilderMode = mode

        switch mode {
        case .straightLine:
            resetLatestNavigationAlternatives()
            syncDraftRouteToStraightLineStops(
                status: routeBuilderStops.isEmpty
                    ? .localized(TeleportStrings.routeBuilderEmpty)
                    : .localized(TeleportStrings.routeBuilderUpdated(routeBuilderStopCount))
            )
        case .navigation:
            guard routeBuilderStops.count > 1 else {
                resetLatestNavigationAlternatives(prefixWaypointCount: routeBuilderStops.count)
                draftRouteWaypoints = routeBuilderStops.map { RouteWaypoint(coordinate: $0) }
                return
            }

            let task = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await rebuildNavigationRouteFromCurrentStops()
            }
            routeBuilderNavigationTask = task
        }
    }

    func setRouteBuilderNavigationTransport(_ transport: RouteBuilderNavigationTransport) {
        guard routeBuilderNavigationTransport != transport else {
            return
        }

        routeBuilderNavigationTransport = transport

        guard routeBuilderMode == .navigation else {
            return
        }

        routeBuilderNavigationTask?.cancel()
        routeBuilderNavigationTask = nil

        guard routeBuilderStops.count > 1 else {
            resetLatestNavigationAlternatives(prefixWaypointCount: routeBuilderStops.count)
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await rebuildNavigationRouteFromCurrentStops()
        }
        routeBuilderNavigationTask = task
    }

    func selectLatestRouteBuilderAlternative(index: Int) {
        guard routeBuilderLatestSegmentAlternatives.indices.contains(index) else {
            return
        }

        routeBuilderSelectedAlternativeIndex = index
        let selectedAlternative = routeBuilderLatestSegmentAlternatives[index]
        let preservedPrefix = Array(draftRouteWaypoints.prefix(routeBuilderLatestSegmentPrefixWaypointCount))
        draftRouteWaypoints = preservedPrefix + selectedAlternative.waypoints
        statusMessage = .localized(
            TeleportStrings.routeBuilderSelectedAlternative(
                index + 1,
                totalCount: routeBuilderLatestSegmentAlternatives.count
            )
        )
    }

    func removeLastRouteBuilderWaypoint() {
        guard !routeBuilderStops.isEmpty else {
            return
        }

        routeBuilderNavigationTask?.cancel()
        routeBuilderNavigationTask = nil
        isRouteBuilderResolvingNavigation = false

        routeBuilderStops.removeLast()

        switch routeBuilderMode {
        case .straightLine:
            syncDraftRouteToStraightLineStops(
                status: routeBuilderStops.isEmpty
                    ? .localized(TeleportStrings.routeBuilderEmpty)
                    : .localized(TeleportStrings.routeBuilderUpdated(routeBuilderStopCount))
            )
        case .navigation:
            guard routeBuilderStops.count > 1 else {
                resetLatestNavigationAlternatives(prefixWaypointCount: routeBuilderStops.count)
                draftRouteWaypoints = routeBuilderStops.map { RouteWaypoint(coordinate: $0) }
                statusMessage =
                    routeBuilderStops.isEmpty
                    ? .localized(TeleportStrings.routeBuilderEmpty)
                    : .localized(TeleportStrings.routeBuilderUpdated(routeBuilderStopCount))
                return
            }

            let task = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await rebuildNavigationRouteFromCurrentStops()
            }
            routeBuilderNavigationTask = task
        }
    }

    func cancelRouteBuilder() {
        clearRouteBuilderDraft()
        routePlaybackState = .idle
        statusMessage = .localized(TeleportStrings.routeBuilderCanceled)
    }

    func finalizeRouteBuilder() {
        guard routeBuilderCanFinalize else {
            statusMessage = .localized(TeleportStrings.routeBuilderNeedsTwoPoints)
            return
        }

        let route = SimulatedRoute(
            name: String(localized: TeleportStrings.routeBuilderDefaultName),
            source: routeBuilderMode == .navigation ? .navigation : .drawn,
            waypoints: draftRouteWaypoints
        )

        loadedRoute = route
        clearRouteBuilderDraft()
        routePlaybackState = .ready

        if let startCoordinate = loadedRouteStartDisplayCoordinate {
            suppressPickedLocationPin = false
            latitudeText = String(format: "%.6f", startCoordinate.latitude)
            longitudeText = String(format: "%.6f", startCoordinate.longitude)
        }

        statusMessage = .localized(
            TeleportStrings.loadedRoute(route.name, pointCount: route.pointCount)
        )
    }

    private func appendStraightLineStop(_ displayedCoordinate: LocationCoordinate) {
        let simulationCoordinate = ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: displayedCoordinate)
        guard !isDuplicateRouteBuilderStop(simulationCoordinate) else {
            return
        }

        routeBuilderStops.append(simulationCoordinate)
        syncDraftRouteToStraightLineStops(
            status: .localized(TeleportStrings.routeBuilderAddedPoint(routeBuilderStopCount))
        )
    }

    private func appendNavigationStop(_ displayedCoordinate: LocationCoordinate) async {
        let simulationCoordinate = ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: displayedCoordinate)
        guard !isDuplicateRouteBuilderStop(simulationCoordinate) else {
            routeBuilderNavigationTask = nil
            return
        }

        if routeBuilderStops.isEmpty {
            routeBuilderStops.append(simulationCoordinate)
            draftRouteWaypoints = [RouteWaypoint(coordinate: simulationCoordinate)]
            resetLatestNavigationAlternatives(prefixWaypointCount: draftRouteWaypoints.count)
            statusMessage = .localized(TeleportStrings.routeBuilderAddedPoint(routeBuilderStopCount))
            routeBuilderNavigationTask = nil
            return
        }

        isRouteBuilderResolvingNavigation = true
        statusMessage = .localized(TeleportStrings.routeBuilderRoutingSegment)

        do {
            let service = NavigationRouteSuggestionService()
            let startDisplayCoordinate = ChinaCoordinateTransform.displayCoordinate(for: routeBuilderStops.last!)
            let suggestedAlternatives = try await service.suggestedAlternatives(
                from: startDisplayCoordinate,
                to: displayedCoordinate,
                transport: routeBuilderNavigationTransport,
                requestsAlternates: true
            )
            try Task.checkCancellation()

            guard !suggestedAlternatives.isEmpty else {
                throw NavigationRouteSuggestionError.invalidRouteGeometry
            }

            let alternatives = suggestedAlternatives.map {
                RouteBuilderNavigationAlternative(
                    waypoints: $0.waypoints,
                    distanceMeters: $0.distanceMeters,
                    expectedTravelTime: $0.expectedTravelTime
                )
            }
            let prefixWaypointCount = draftRouteWaypoints.count
            routeBuilderStops.append(simulationCoordinate)
            applyLatestNavigationAlternatives(alternatives, prefixWaypointCount: prefixWaypointCount)
            statusMessage = .localized(
                TeleportStrings.routeBuilderAddedNavigationStop(
                    routeBuilderStopCount,
                    pointCount: routeBuilderWaypointCount
                )
            )
        } catch is CancellationError {
        } catch {
            resetLatestNavigationAlternatives(prefixWaypointCount: draftRouteWaypoints.count)
            statusMessage = .localized(
                TeleportStrings.routeBuilderNavigationFailed(error.localizedDescription)
            )
        }

        isRouteBuilderResolvingNavigation = false
        routeBuilderNavigationTask = nil
    }

    private func rebuildNavigationRouteFromCurrentStops() async {
        guard routeBuilderStops.count > 1 else {
            draftRouteWaypoints = routeBuilderStops.map { RouteWaypoint(coordinate: $0) }
            isRouteBuilderResolvingNavigation = false
            routeBuilderNavigationTask = nil
            return
        }

        isRouteBuilderResolvingNavigation = true
        statusMessage = .localized(TeleportStrings.routeBuilderRoutingSegment)

        do {
            let service = NavigationRouteSuggestionService()
            var rebuiltWaypoints = [RouteWaypoint(coordinate: routeBuilderStops[0])]
            var latestAlternatives: [RouteBuilderNavigationAlternative] = []
            var latestPrefixWaypointCount = 1
            let segmentCount = max(routeBuilderStops.count - 1, 0)

            for (segmentIndex, stopPair) in zip(routeBuilderStops, routeBuilderStops.dropFirst()).enumerated() {
                try Task.checkCancellation()
                let suggestedAlternatives = try await service.suggestedAlternatives(
                    from: ChinaCoordinateTransform.displayCoordinate(for: stopPair.0),
                    to: ChinaCoordinateTransform.displayCoordinate(for: stopPair.1),
                    transport: routeBuilderNavigationTransport,
                    requestsAlternates: segmentIndex == segmentCount - 1
                )
                try Task.checkCancellation()

                let alternatives = suggestedAlternatives.map {
                    RouteBuilderNavigationAlternative(
                        waypoints: $0.waypoints,
                        distanceMeters: $0.distanceMeters,
                        expectedTravelTime: $0.expectedTravelTime
                    )
                }

                guard !alternatives.isEmpty else {
                    throw NavigationRouteSuggestionError.invalidRouteGeometry
                }

                if segmentIndex == segmentCount - 1 {
                    latestPrefixWaypointCount = rebuiltWaypoints.count
                    latestAlternatives = alternatives
                    let selectedIndex = min(routeBuilderSelectedAlternativeIndex, alternatives.count - 1)
                    rebuiltWaypoints.append(contentsOf: alternatives[selectedIndex].waypoints)
                } else {
                    rebuiltWaypoints.append(contentsOf: alternatives[0].waypoints)
                }
            }

            draftRouteWaypoints = rebuiltWaypoints
            routeBuilderLatestSegmentAlternatives = latestAlternatives
            routeBuilderLatestSegmentPrefixWaypointCount = latestPrefixWaypointCount
            routeBuilderSelectedAlternativeIndex = min(
                routeBuilderSelectedAlternativeIndex,
                max(latestAlternatives.count - 1, 0)
            )
            statusMessage = .localized(
                TeleportStrings.routeBuilderAddedNavigationStop(
                    routeBuilderStopCount,
                    pointCount: routeBuilderWaypointCount
                )
            )
        } catch is CancellationError {
        } catch {
            draftRouteWaypoints = routeBuilderStops.map { RouteWaypoint(coordinate: $0) }
            resetLatestNavigationAlternatives(prefixWaypointCount: draftRouteWaypoints.count)
            statusMessage = .localized(
                TeleportStrings.routeBuilderNavigationFailed(error.localizedDescription)
            )
        }

        isRouteBuilderResolvingNavigation = false
        routeBuilderNavigationTask = nil
    }

    private func syncDraftRouteToStraightLineStops(status: UserFacingText) {
        draftRouteWaypoints = routeBuilderStops.map { RouteWaypoint(coordinate: $0) }
        statusMessage = status
    }

    private func applyLatestNavigationAlternatives(
        _ alternatives: [RouteBuilderNavigationAlternative],
        prefixWaypointCount: Int,
        preferredSelectedIndex: Int = 0
    ) {
        routeBuilderLatestSegmentAlternatives = alternatives
        routeBuilderLatestSegmentPrefixWaypointCount = prefixWaypointCount
        routeBuilderSelectedAlternativeIndex = min(preferredSelectedIndex, max(alternatives.count - 1, 0))

        let preservedPrefix = Array(draftRouteWaypoints.prefix(prefixWaypointCount))
        draftRouteWaypoints = preservedPrefix + alternatives[routeBuilderSelectedAlternativeIndex].waypoints
    }

    private func resetLatestNavigationAlternatives(prefixWaypointCount: Int = 0) {
        routeBuilderLatestSegmentAlternatives = []
        routeBuilderSelectedAlternativeIndex = 0
        routeBuilderLatestSegmentPrefixWaypointCount = prefixWaypointCount
    }

    private func isDuplicateRouteBuilderStop(_ coordinate: LocationCoordinate) -> Bool {
        guard let lastStop = routeBuilderStops.last else {
            return false
        }

        return lastStop.isApproximatelyEqual(to: coordinate)
    }
}
