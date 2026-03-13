import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

extension UTType {
    fileprivate static let teleportGPX = UTType(filenameExtension: "gpx") ?? .xml
}

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

    func saveCurrentRouteToApp() {
        guard let loadedRoute else {
            return
        }

        upsertSavedRoute(loadedRoute)

        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.savedRouteInApp(loadedRoute.name))
    }

    func updateCurrentSavedRouteInApp() {
        guard let loadedRoute, let existingIndex = loadedSavedRouteIndex else {
            return
        }

        savedRoutes[existingIndex] = loadedRoute
        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.updatedSavedRouteInApp(loadedRoute.name))
    }

    func saveCurrentRouteToAppAsNew() {
        guard let loadedRoute else {
            return
        }

        let defaultName = suggestedDuplicateRouteName(for: loadedRoute.name)
        guard
            let routeName = promptForRouteName(
                title: TeleportStrings.saveRoutePromptTitle,
                message: TeleportStrings.saveRoutePromptMessage,
                defaultName: defaultName,
                actionTitle: TeleportStrings.routeSaveAsNew
            )
        else {
            return
        }

        let savedRoute = SimulatedRoute(
            name: routeName,
            source: loadedRoute.source,
            waypoints: loadedRoute.waypoints
        )

        self.loadedRoute = savedRoute
        upsertSavedRoute(savedRoute)
        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.savedRouteAsNewCopy(savedRoute.name))
    }

    func loadSavedRoute(_ route: SimulatedRoute) {
        stopRoutePlayback(resetToReadyState: false)
        isRouteBuilderActive = false
        draftRouteWaypoints = []
        loadedRoute = route
        routePlaybackState = .ready

        if let startCoordinate = loadedRouteStartDisplayCoordinate {
            suppressPickedLocationPin = false
            latitudeText = String(format: "%.6f", startCoordinate.latitude)
            longitudeText = String(format: "%.6f", startCoordinate.longitude)
        }

        statusMessage = .localized(TeleportStrings.loadedSavedRoute(route.name))
    }

    func deleteSavedRoute(_ route: SimulatedRoute) {
        savedRoutes.removeAll { $0.id == route.id }
        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.deletedSavedRoute(route.name))
    }

    func renameSavedRoute(_ route: SimulatedRoute) {
        guard
            let routeName = promptForRouteName(
                title: TeleportStrings.renameRoutePromptTitle,
                message: TeleportStrings.renameRoutePromptMessage,
                defaultName: route.name,
                actionTitle: TeleportStrings.savedRouteRename
            )
        else {
            return
        }

        guard let existingIndex = savedRoutes.firstIndex(where: { $0.id == route.id }) else {
            return
        }

        savedRoutes[existingIndex].name = routeName

        if loadedRoute?.id == route.id {
            loadedRoute?.name = routeName
        }

        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.renamedSavedRoute(routeName))
    }

    func exportCurrentRouteAsGPX() {
        guard let loadedRoute, currentRouteCanBeExportedAsGPX else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.teleportGPX]
        panel.nameFieldStringValue = suggestedGPXFileName(for: loadedRoute)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = GPXRouteExporter().export(route: loadedRoute)
            try data.write(to: url, options: .atomic)
            statusMessage = .localized(TeleportStrings.exportedRouteAsGPX(loadedRoute.name))
        } catch {
            let message = UserFacingText.localized(
                TeleportStrings.failedToExportGPX(error.localizedDescription)
            )
            statusMessage = message
        }
    }

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

    private func suggestedGPXFileName(for route: SimulatedRoute) -> String {
        let trimmedName = route.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "route" : trimmedName
        let sanitized = baseName.replacingOccurrences(of: "/", with: "-")
        return sanitized + ".gpx"
    }

    private func suggestedDuplicateRouteName(for name: String) -> String {
        let trimmedName = normalizedRouteName(from: name, fallback: "Route")
        return trimmedName + " Copy"
    }

    private func promptForRouteName(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        defaultName: String,
        actionTitle: LocalizedStringResource
    ) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: title)
        alert.informativeText = String(localized: message)

        let textField = NSTextField(string: defaultName)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: String(localized: actionTitle))
        alert.addButton(withTitle: String(localized: TeleportStrings.cancel))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return normalizedRouteName(from: textField.stringValue, fallback: defaultName)
    }

    private func normalizedRouteName(from value: String, fallback: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedValue.isEmpty {
            return trimmedValue
        }

        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? "Route" : trimmedFallback
    }

    private func upsertSavedRoute(_ route: SimulatedRoute) {
        if let existingIndex = savedRoutes.firstIndex(where: { $0.id == route.id }) {
            savedRoutes[existingIndex] = route
        } else {
            savedRoutes.insert(route, at: 0)
        }
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
