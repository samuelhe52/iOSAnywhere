import Foundation
import MapKit

fileprivate struct SuggestedNavigationPoint: Sendable {
    let coordinate: LocationCoordinate
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
    func suggestedPoints(
        from start: LocationCoordinate,
        to end: LocationCoordinate
    ) async throws -> [SuggestedNavigationPoint] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.clLocationCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.clLocationCoordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw NavigationRouteSuggestionError.noRouteFound
        }

        let coordinates = route.polyline.coordinates.map(LocationCoordinate.init)
        guard coordinates.count > 1 else {
            throw NavigationRouteSuggestionError.invalidRouteGeometry
        }

        let segmentDistances = zip(coordinates, coordinates.dropFirst()).map { $0.distance(to: $1) }
        let totalDistance = segmentDistances.reduce(0, +)

        var points: [SuggestedNavigationPoint] = [
            SuggestedNavigationPoint(coordinate: coordinates[0], expectedTravelTime: nil)
        ]
        for (index, coordinate) in coordinates.dropFirst().enumerated() {
            let expectedTravelTime: TimeInterval?
            if totalDistance > 0, route.expectedTravelTime > 0 {
                expectedTravelTime = route.expectedTravelTime * (segmentDistances[index] / totalDistance)
            } else {
                expectedTravelTime = nil
            }

            points.append(
                SuggestedNavigationPoint(
                    coordinate: coordinate,
                    expectedTravelTime: expectedTravelTime
                )
            )
        }

        return points
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
            syncDraftRouteToStraightLineStops(
                status: routeBuilderStops.isEmpty
                    ? .localized(TeleportStrings.routeBuilderEmpty)
                    : .localized(TeleportStrings.routeBuilderUpdated(routeBuilderStopCount))
            )
        case .navigation:
            guard routeBuilderStops.count > 1 else {
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
            statusMessage = .localized(TeleportStrings.routeBuilderAddedPoint(routeBuilderStopCount))
            routeBuilderNavigationTask = nil
            return
        }

        isRouteBuilderResolvingNavigation = true
        statusMessage = .localized(TeleportStrings.routeBuilderRoutingSegment)

        do {
            let service = NavigationRouteSuggestionService()
            let startDisplayCoordinate = ChinaCoordinateTransform.displayCoordinate(for: routeBuilderStops.last!)
            let suggestedPoints = try await service.suggestedPoints(
                from: startDisplayCoordinate,
                to: displayedCoordinate
            )
            try Task.checkCancellation()

            let appendedWaypoints = suggestedPoints.dropFirst().map { point in
                RouteWaypoint(
                    coordinate: ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: point.coordinate),
                    expectedTravelTime: point.expectedTravelTime
                )
            }

            guard !appendedWaypoints.isEmpty else {
                throw NavigationRouteSuggestionError.invalidRouteGeometry
            }

            routeBuilderStops.append(simulationCoordinate)
            draftRouteWaypoints.append(contentsOf: appendedWaypoints)
            statusMessage = .localized(
                TeleportStrings.routeBuilderAddedNavigationStop(
                    routeBuilderStopCount,
                    pointCount: routeBuilderWaypointCount
                )
            )
        } catch is CancellationError {
        } catch {
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

            for stopPair in zip(routeBuilderStops, routeBuilderStops.dropFirst()) {
                try Task.checkCancellation()
                let suggestedPoints = try await service.suggestedPoints(
                    from: ChinaCoordinateTransform.displayCoordinate(for: stopPair.0),
                    to: ChinaCoordinateTransform.displayCoordinate(for: stopPair.1)
                )
                try Task.checkCancellation()

                let segmentWaypoints = suggestedPoints.dropFirst().map { point in
                    RouteWaypoint(
                        coordinate: ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: point.coordinate),
                        expectedTravelTime: point.expectedTravelTime
                    )
                }

                rebuiltWaypoints.append(contentsOf: segmentWaypoints)
            }

            draftRouteWaypoints = rebuiltWaypoints
            statusMessage = .localized(
                TeleportStrings.routeBuilderAddedNavigationStop(
                    routeBuilderStopCount,
                    pointCount: routeBuilderWaypointCount
                )
            )
        } catch is CancellationError {
        } catch {
            draftRouteWaypoints = routeBuilderStops.map { RouteWaypoint(coordinate: $0) }
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

    private func isDuplicateRouteBuilderStop(_ coordinate: LocationCoordinate) -> Bool {
        guard let lastStop = routeBuilderStops.last else {
            return false
        }

        return lastStop.isApproximatelyEqual(to: coordinate)
    }
}
