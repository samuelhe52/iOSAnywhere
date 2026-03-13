import Foundation
import OSLog

extension AppViewModel {
    func importGPXRoute(from url: URL) async {
        stopRoutePlayback(resetToReadyState: false)
        isRouteBuilderActive = false
        draftRouteWaypoints = []

        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let parser = GPXRouteParser()
            let route = try parser.parse(
                data: data,
                fallbackName: url.deletingPathExtension().lastPathComponent
            )

            loadedRoute = route
            routePlaybackState = .ready

            if let startCoordinate = loadedRouteStartDisplayCoordinate {
                suppressPickedLocationPin = false
                latitudeText = String(format: "%.6f", startCoordinate.latitude)
                longitudeText = String(format: "%.6f", startCoordinate.longitude)
            }

            statusMessage = .localized(
                TeleportStrings.loadedRoute(route.name, pointCount: route.pointCount)
            )
        } catch {
            loadedRoute = nil
            let message = UserFacingText.localized(
                TeleportStrings.failedToImportGPX(error.localizedDescription)
            )
            routePlaybackState = .failed(message)
            statusMessage = message
        }
    }

    func clearLoadedRoute() {
        stopRoutePlayback(resetToReadyState: false)
        loadedRoute = nil
        draftRouteWaypoints = []
        isRouteBuilderActive = false
        routePlaybackState = .idle
        statusMessage = .localized(TeleportStrings.clearedLoadedRoute)
    }

    func startRoutePlayback() async {
        stopMovementControl(commitCurrentCoordinateToTextFields: false)

        guard let route = loadedRoute else {
            let message = UserFacingText.localized(TeleportStrings.noRouteLoaded)
            routePlaybackState = .failed(message)
            statusMessage = message
            return
        }

        guard route.waypoints.count > 1 else {
            let message = UserFacingText.localized(TeleportStrings.routeRequiresAtLeastTwoPoints)
            routePlaybackState = .failed(message)
            statusMessage = message
            return
        }

        guard routePlaybackAvailable else {
            let message = UserFacingText.localized(TeleportStrings.routePlaybackRequiresConnection)
            routePlaybackState = .failed(message)
            statusMessage = message
            return
        }

        switch routePlaybackState {
        case .playing:
            return
        case .idle, .ready, .paused, .completed, .failed:
            break
        }

        do {
            let target = try await resolvedSimulationTargetForPlayback()
            let initialProgress = playbackStartProgress(for: route)
            routePlaybackState = .playing(initialProgress)

            routePlaybackTask?.cancel()
            routePlaybackTask = Task {
                await runRoutePlayback(route: route, initialProgress: initialProgress, target: target)
            }
        } catch {
            handleRoutePlaybackError(error)
        }
    }

    func pauseRoutePlayback() {
        guard case .playing(let progress) = routePlaybackState else {
            return
        }

        routePlaybackState = .paused(progress)
        routePlaybackTask?.cancel()
        routePlaybackTask = nil

        if let routeName = loadedRoute?.name {
            statusMessage = .localized(TeleportStrings.pausedRoute(routeName))
        }
    }

    func stopRoutePlayback(resetToReadyState: Bool = true) {
        routePlaybackTask?.cancel()
        routePlaybackTask = nil

        guard loadedRoute != nil else {
            routePlaybackState = .idle
            return
        }

        if resetToReadyState {
            routePlaybackState = .ready

            if let routeName = loadedRoute?.name {
                statusMessage = .localized(TeleportStrings.stoppedRoute(routeName))
            }
        }
    }

    private struct SimulationPlaybackTarget {
        let device: Device
        let service: LocationSimulationService
    }

    private struct PlaybackInterpolationStep {
        let coordinate: LocationCoordinate
        let delaySeconds: TimeInterval
        let traveledDistanceMeters: Double
        let progressWaypointIndex: Int
    }

    private func handleRoutePlaybackError(_ error: Error) {
        routePlaybackTask?.cancel()
        routePlaybackTask = nil

        let message = UserFacingText.verbatim(error.localizedDescription)
        routePlaybackState = .failed(message)
        statusMessage = message
        TeleportLog.simulation.error("Route playback failed: \(error.localizedDescription, privacy: .public)")
    }

    private func resolvedSimulationTargetForPlayback() async throws -> SimulationPlaybackTarget {
        guard let selectedDevice else {
            throw ServiceError.invalidSelection
        }

        let device: Device
        if selectedDevice.kind.isPhysicalDevice && connectionState == .connected {
            device = selectedDevice
        } else if let refreshedDevice = await refreshedDeviceForAction(selectedDevice, stateTarget: .simulation) {
            device = refreshedDevice
        } else {
            throw ServiceError.invalidSelection
        }

        guard let service = registry.service(for: device.kind) else {
            throw ServiceError.unavailable(
                String(localized: TeleportStrings.noServiceAvailable(for: device.kind.rawValue))
            )
        }

        if device.kind.isPhysicalDevice && showsUSBApprovalReminder {
            showsUSBPrivilegeNotice = true
            throw ServiceError.unavailable(String(localized: TeleportStrings.reviewAdministratorApproval))
        }

        let hasActiveSimulationSession = await service.hasActiveSimulationSession()
        if device.kind.isPhysicalDevice && !hasActiveSimulationSession {
            simulationState = .starting
            statusMessage = .localized(TeleportStrings.startingPhysicalDeviceSimulation)
        }

        return SimulationPlaybackTarget(device: device, service: service)
    }

    private func playbackStartProgress(for route: SimulatedRoute) -> RoutePlaybackProgress {
        switch routePlaybackState {
        case .paused(let progress) where progress.routeID == route.id:
            return progress
        case .completed where loadedRoute?.id == route.id:
            return makeRoutePlaybackProgress(for: route, waypointIndex: 0)
        case .playing(let progress) where progress.routeID == route.id:
            return progress
        case .idle, .ready, .paused, .completed, .failed, .playing:
            return makeRoutePlaybackProgress(for: route, waypointIndex: 0)
        }
    }

    private func runRoutePlayback(
        route: SimulatedRoute,
        initialProgress: RoutePlaybackProgress,
        target: SimulationPlaybackTarget
    ) async {
        TeleportLog.simulation.info(
            "Starting route playback for \(route.name, privacy: .public) on \(target.device.logLabel, privacy: .public)"
        )

        defer {
            routePlaybackTask = nil
        }

        do {
            var currentProgress = initialProgress
            let waypoints = route.waypoints
            let totalRouteDistanceMeters = route.totalDistanceMeters

            if currentProgress.waypointIndex == 0 || currentProgress.currentCoordinate == nil {
                let startCoordinate = ChinaCoordinateTransform.displayCoordinate(for: waypoints[0].coordinate)
                try await applyDisplayedSimulationCoordinate(startCoordinate, on: target.device, using: target.service)
                currentProgress = makeRoutePlaybackProgress(for: route, waypointIndex: 0)
                routePlaybackState = .playing(currentProgress)
            }

            if currentProgress.waypointIndex >= waypoints.count - 1 {
                routePlaybackState = .completed(currentProgress)
                statusMessage = .localized(TeleportStrings.completedRoute(route.name))
                return
            }

            for nextIndex in (currentProgress.waypointIndex + 1)..<waypoints.count {
                let previousIndex = nextIndex - 1
                let segmentDelay = routeSegmentDelay(
                    from: waypoints[previousIndex],
                    to: waypoints[nextIndex]
                )

                let smoothedSteps = smoothedPlaybackSteps(
                    from: waypoints[previousIndex],
                    to: waypoints[nextIndex],
                    totalDelaySeconds: segmentDelay,
                    traveledDistanceBeforeSegment: currentProgress.traveledDistanceMeters,
                    totalRouteDistanceMeters: totalRouteDistanceMeters,
                    nextWaypointIndex: nextIndex,
                    route: route
                )

                for step in smoothedSteps {
                    if step.delaySeconds > 0 {
                        try await Task.sleep(nanoseconds: UInt64(step.delaySeconds * 1_000_000_000))
                    }

                    try Task.checkCancellation()

                    let displayedCoordinate = ChinaCoordinateTransform.displayCoordinate(for: step.coordinate)
                    try await applyDisplayedSimulationCoordinate(
                        displayedCoordinate,
                        on: target.device,
                        using: target.service,
                        moving: true
                    )

                    try Task.checkCancellation()

                    currentProgress = makeRoutePlaybackProgress(
                        for: route,
                        waypointIndex: step.progressWaypointIndex,
                        displayedCoordinate: displayedCoordinate,
                        traveledDistanceMeters: step.traveledDistanceMeters,
                        totalDistanceMeters: totalRouteDistanceMeters
                    )
                    routePlaybackState = .playing(currentProgress)
                }

                statusMessage = .localized(
                    TeleportStrings.playingRoute(
                        route.name,
                        pointNumber: nextIndex + 1,
                        totalPoints: waypoints.count
                    )
                )
            }

            routePlaybackState = .completed(currentProgress)
            statusMessage = .localized(TeleportStrings.completedRoute(route.name))
            TeleportLog.simulation.info(
                "Completed route playback for \(route.name, privacy: .public) on \(target.device.logLabel, privacy: .public)"
            )
        } catch is CancellationError {
            TeleportLog.simulation.debug("Route playback cancelled")
        } catch {
            handleRoutePlaybackError(error)
        }
    }

    private func routeSegmentDelay(from start: RouteWaypoint, to end: RouteWaypoint) -> TimeInterval {
        playbackSegmentDelay(from: start, to: end)
    }

    private func makeRoutePlaybackProgress(for route: SimulatedRoute, waypointIndex: Int) -> RoutePlaybackProgress {
        let clampedIndex = min(max(waypointIndex, 0), max(route.waypoints.count - 1, 0))
        let displayedCoordinate =
            route.waypoints.indices.contains(clampedIndex)
            ? ChinaCoordinateTransform.displayCoordinate(for: route.waypoints[clampedIndex].coordinate)
            : nil

        let traveledDistanceMeters: Double
        if clampedIndex > 0 {
            traveledDistanceMeters = zip(
                route.waypoints.prefix(clampedIndex), route.waypoints.dropFirst().prefix(clampedIndex)
            )
            .reduce(0) { total, pair in
                total + pair.0.coordinate.distance(to: pair.1.coordinate)
            }
        } else {
            traveledDistanceMeters = 0
        }

        let totalDistanceMeters = route.totalDistanceMeters

        return RoutePlaybackProgress(
            routeID: route.id,
            waypointIndex: clampedIndex,
            waypointCount: route.waypoints.count,
            currentCoordinate: displayedCoordinate,
            traveledDistanceMeters: traveledDistanceMeters,
            totalDistanceMeters: totalDistanceMeters
        )
    }

    private func makeRoutePlaybackProgress(
        for route: SimulatedRoute,
        waypointIndex: Int,
        displayedCoordinate: LocationCoordinate,
        traveledDistanceMeters: Double,
        totalDistanceMeters: Double
    ) -> RoutePlaybackProgress {
        RoutePlaybackProgress(
            routeID: route.id,
            waypointIndex: waypointIndex,
            waypointCount: route.waypoints.count,
            currentCoordinate: displayedCoordinate,
            traveledDistanceMeters: traveledDistanceMeters,
            totalDistanceMeters: totalDistanceMeters
        )
    }

    private func smoothedPlaybackSteps(
        from start: RouteWaypoint,
        to end: RouteWaypoint,
        totalDelaySeconds: TimeInterval,
        traveledDistanceBeforeSegment: Double,
        totalRouteDistanceMeters: Double,
        nextWaypointIndex: Int,
        route: SimulatedRoute
    ) -> [PlaybackInterpolationStep] {
        let segmentDistanceMeters = start.coordinate.distance(to: end.coordinate)
        let timeStepCount =
            totalDelaySeconds > 0
            ? max(1, Int(ceil(totalDelaySeconds / routePlaybackSmoothingIntervalSeconds)))
            : 1
        let distanceStepCount =
            segmentDistanceMeters > 0
            ? max(1, Int(ceil(segmentDistanceMeters / maximumRouteStepDistanceMeters)))
            : 1
        let stepCount = max(timeStepCount, distanceStepCount)
        let perStepDelay = stepCount > 0 ? totalDelaySeconds / Double(stepCount) : 0

        return (1...stepCount).map { stepIndex in
            let fraction = Double(stepIndex) / Double(stepCount)
            let coordinate = start.coordinate.interpolated(to: end.coordinate, fraction: fraction)
            let traveledDistanceMeters = min(
                traveledDistanceBeforeSegment + segmentDistanceMeters * fraction,
                totalRouteDistanceMeters
            )
            let progressWaypointIndex = stepIndex == stepCount ? nextWaypointIndex : max(nextWaypointIndex - 1, 0)

            return PlaybackInterpolationStep(
                coordinate: coordinate,
                delaySeconds: perStepDelay,
                traveledDistanceMeters: traveledDistanceMeters,
                progressWaypointIndex: progressWaypointIndex
            )
        }
    }
}
