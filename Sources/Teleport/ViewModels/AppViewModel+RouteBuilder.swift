import Foundation

extension AppViewModel {
    func startRouteBuilder() {
        stopRoutePlayback(resetToReadyState: false)
        loadedRoute = nil
        draftRouteWaypoints = []
        isRouteBuilderActive = true
        routePlaybackState = .idle
        statusMessage = .localized(TeleportStrings.routeBuilderStarted)
    }

    func addRouteBuilderWaypoint(_ displayedCoordinate: LocationCoordinate) {
        guard isRouteBuilderActive else {
            return
        }

        let simulationCoordinate = ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: displayedCoordinate)

        if let lastWaypoint = draftRouteWaypoints.last,
            lastWaypoint.coordinate.isApproximatelyEqual(to: simulationCoordinate)
        {
            return
        }

        draftRouteWaypoints.append(RouteWaypoint(coordinate: simulationCoordinate))
        statusMessage = .localized(
            TeleportStrings.routeBuilderAddedPoint(draftRouteWaypoints.count)
        )
    }

    func removeLastRouteBuilderWaypoint() {
        guard !draftRouteWaypoints.isEmpty else {
            return
        }

        draftRouteWaypoints.removeLast()
        statusMessage =
            draftRouteWaypoints.isEmpty
            ? .localized(TeleportStrings.routeBuilderEmpty)
            : .localized(TeleportStrings.routeBuilderUpdated(draftRouteWaypoints.count))
    }

    func cancelRouteBuilder() {
        draftRouteWaypoints = []
        isRouteBuilderActive = false
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
            source: .drawn,
            waypoints: draftRouteWaypoints
        )

        loadedRoute = route
        draftRouteWaypoints = []
        isRouteBuilderActive = false
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
}
