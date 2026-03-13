import Foundation
import OSLog

extension AppViewModel {
    var selectedDevice: Device? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var selectedDeviceRequiresAdministratorApproval: Bool {
        selectedDevice?.kind.isPhysicalDevice == true
    }

    var showsUSBApprovalReminder: Bool {
        guard selectedDeviceRequiresAdministratorApproval else {
            return false
        }

        if suppressUSBPrivilegeNotice {
            return false
        }

        return acknowledgedUSBPrivilegeDeviceID != selectedDeviceID
    }

    func refreshDevices() async {
        TeleportLog.devices.info("Starting device discovery across simulator and physical-device services")
        discoveryState = .discovering
        statusMessage = .localized(TeleportStrings.scanningDevices)
        let previousSelectionID = selectedDeviceID

        do {
            async let simulatorDevices = registry.service(for: .simulator)?.discoverDevices() ?? []
            async let physicalDevices = registry.service(for: .physicalUSB)?.discoverDevices() ?? []
            let discovered = try await simulatorDevices + physicalDevices
            devices = discovered.sorted { $0.name < $1.name }
            if let previousSelectionID, devices.contains(where: { $0.id == previousSelectionID }) {
                selectedDeviceID = previousSelectionID
            } else {
                selectedDeviceID = devices.first?.id
            }
            await updateSelectedPythonRuntimeNote()
            discoveryState = .ready
            statusMessage =
                devices.isEmpty
                ? .localized(TeleportStrings.noDevicesFound)
                : .localized(TeleportStrings.foundDevices(devices.count))
            TeleportLog.devices.info(
                "Device discovery completed with \(self.devices.count) device(s); selected device: \(self.selectedDevice?.logLabel ?? "none", privacy: .public)"
            )
        } catch {
            let message = UserFacingText.verbatim(error.localizedDescription)
            discoveryState = .failed(message)
            statusMessage = message
            TeleportLog.devices.error(
                "Device discovery failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func connectSelectedDevice() async {
        guard connectionState != .connecting else {
            TeleportLog.devices.debug(
                "Ignoring duplicate connect request while a connection attempt is already in progress")
            return
        }

        guard let selectedDevice else {
            connectionState = .failed(.localized(TeleportStrings.selectDeviceFirst))
            TeleportLog.devices.warning("Connect requested without a selected device")
            return
        }

        connectionState = .connecting
        statusMessage = .localized(TeleportStrings.connectingToDevice(selectedDevice.name))

        guard let device = await refreshedDeviceForAction(selectedDevice, stateTarget: .connection) else {
            return
        }
        guard let service = registry.service(for: device.kind) else {
            connectionState = .failed(
                .localized(TeleportStrings.noServiceAvailable(for: device.kind.rawValue))
            )
            TeleportLog.devices.error(
                "No service available while connecting to \(device.logLabel, privacy: .public)"
            )
            return
        }

        TeleportLog.devices.info("Connecting to \(device.logLabel, privacy: .public)")
        statusMessage = .localized(TeleportStrings.connectingToDevice(device.name))

        do {
            try await service.connect(to: device)
            connectionState = .connected
            statusMessage = .localized(TeleportStrings.connectedToDevice(device.name))
            TeleportLog.devices.info("Connected to \(device.logLabel, privacy: .public)")
        } catch {
            let message = UserFacingText.verbatim(error.localizedDescription)
            connectionState = .failed(message)
            statusMessage = message
            TeleportLog.devices.error(
                "Connection failed for \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func disconnectSelectedDevice() async {
        stopMovementControl(commitCurrentCoordinateToTextFields: false)
        stopRoutePlayback(resetToReadyState: false)

        guard let device = selectedDevice, let service = registry.service(for: device.kind) else {
            connectionState = .disconnected
            TeleportLog.devices.debug("Disconnect requested without an active device/service")
            return
        }

        TeleportLog.devices.info("Disconnecting from \(device.logLabel, privacy: .public)")
        connectionState = .disconnecting
        await service.disconnect()
        connectionState = .disconnected
        simulationState = .idle
        showsPythonDependencyGuide = nil
        statusMessage = .localized(TeleportStrings.disconnectedFromDevice(device.name))
        TeleportLog.devices.info("Disconnected from \(device.logLabel, privacy: .public)")
    }

    func simulateSelectedLocation() async {
        stopMovementControl(commitCurrentCoordinateToTextFields: false)
        stopRoutePlayback(resetToReadyState: true)

        guard beginSimulationAction(kind: "simulate") else {
            return
        }
        defer {
            isSimulationActionInFlight = false
        }

        switch simulationState {
        case .starting, .stopping:
            TeleportLog.simulation.debug(
                "Ignoring duplicate simulate request while a simulation action is already in progress")
            return
        case .idle, .failed, .simulating:
            break
        }

        guard let selectedDevice else {
            simulationState = .failed(.localized(TeleportStrings.selectDeviceFirst))
            TeleportLog.simulation.warning("Simulation requested without a selected device")
            return
        }
        let device: Device
        if selectedDevice.kind.isPhysicalDevice && connectionState == .connected {
            device = selectedDevice
        } else {
            guard let refreshedDevice = await refreshedDeviceForAction(selectedDevice, stateTarget: .simulation) else {
                return
            }
            device = refreshedDevice
        }
        guard let service = registry.service(for: device.kind) else {
            simulationState = .failed(
                .localized(TeleportStrings.noServiceAvailable(for: device.kind.rawValue))
            )
            TeleportLog.simulation.error(
                "No service available while simulating on \(device.logLabel, privacy: .public)"
            )
            return
        }
        guard let latitude = Double(latitudeText),
            let longitude = Double(longitudeText)
        else {
            let message = UserFacingText.localized(TeleportStrings.enterValidCoordinates)
            simulationState = .failed(message)
            statusMessage = message
            TeleportLog.simulation.warning(
                "Simulation rejected for \(device.logLabel, privacy: .public) because coordinates were invalid"
            )
            return
        }

        if device.kind.isPhysicalDevice && showsUSBApprovalReminder {
            showsUSBPrivilegeNotice = true
            statusMessage = .localized(TeleportStrings.reviewAdministratorApproval)
            TeleportLog.simulation.info(
                "Showing administrator approval reminder before physical-device simulation for \(device.logLabel, privacy: .public)"
            )
            return
        }

        let coordinate = LocationCoordinate(latitude: latitude, longitude: longitude)
        let simulationCoordinate = ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: coordinate)
        let wasTransformed = simulationCoordinate != coordinate

        TeleportLog.simulation.info(
            "Starting simulation on \(device.logLabel, privacy: .public); displayed coordinate: \(coordinate.formatted, privacy: .private)"
        )
        if wasTransformed {
            TeleportLog.simulation.debug(
                "Applied China coordinate transform for \(device.logLabel, privacy: .public); simulation coordinate: \(simulationCoordinate.formatted, privacy: .private)"
            )
        }
        do {
            let hasActiveSimulationSession = await service.hasActiveSimulationSession()
            let needsPhysicalDeviceStartup = device.kind.isPhysicalDevice && !hasActiveSimulationSession
            if needsPhysicalDeviceStartup {
                simulationState = .starting
                statusMessage = .localized(TeleportStrings.startingPhysicalDeviceSimulation)
                TeleportLog.simulation.info(
                    "Starting physical-device simulation helper for \(device.logLabel, privacy: .public)"
                )
            }

            try await applyDisplayedSimulationCoordinate(coordinate, on: device, using: service)
        } catch {
            handleSimulationError(error)
        }
    }

    func confirmUSBPrivilegeNotice(suppressFuturePrompts: Bool) async {
        if suppressFuturePrompts {
            suppressUSBPrivilegeNotice = true
            defaults.set(true, forKey: AppViewModelPreferences.suppressUSBPrivilegeNotice)
        }
        acknowledgedUSBPrivilegeDeviceID = selectedDeviceID
        showsUSBPrivilegeNotice = false
        await simulateSelectedLocation()
    }

    func dismissUSBPrivilegeNotice() {
        showsUSBPrivilegeNotice = false
        let message = UserFacingText.localized(TeleportStrings.approvalCanceledBeforePrompt)
        simulationState = .failed(message)
        statusMessage = message
        TeleportLog.simulation.warning(
            "Administrator approval reminder was dismissed before physical-device simulation")
    }

    func clearSimulatedLocation() async {
        stopMovementControl(commitCurrentCoordinateToTextFields: false)
        stopRoutePlayback(resetToReadyState: true)

        guard beginSimulationAction(kind: "clear") else {
            return
        }
        defer {
            isSimulationActionInFlight = false
        }

        guard case .simulating = simulationState else {
            return
        }

        guard let selectedDevice else {
            simulationState = .failed(.localized(TeleportStrings.selectDeviceFirst))
            TeleportLog.simulation.warning("Clear simulated location requested without a selected device")
            return
        }
        let device: Device
        if selectedDevice.kind.isPhysicalDevice && connectionState == .connected {
            device = selectedDevice
        } else {
            guard let refreshedDevice = await refreshedDeviceForAction(selectedDevice, stateTarget: .simulation) else {
                return
            }
            device = refreshedDevice
        }
        guard let service = registry.service(for: device.kind) else {
            simulationState = .failed(.localized(TeleportStrings.noServiceAvailable(for: device.kind.rawValue)))
            TeleportLog.simulation.error(
                "No service available while clearing simulation on \(device.logLabel, privacy: .public)"
            )
            return
        }

        TeleportLog.simulation.info("Clearing simulated location on \(device.logLabel, privacy: .public)")
        simulationState = .stopping
        do {
            try await service.clearLocation()
            simulationState = .idle
            showsPythonDependencyGuide = nil
            statusMessage = .localized(TeleportStrings.clearedSimulatedLocation(on: device.name))
            TeleportLog.simulation.info("Cleared simulated location on \(device.logLabel, privacy: .public)")
        } catch {
            handleSimulationError(error)
        }
    }

    func importGPXRoute(from url: URL) async {
        stopRoutePlayback(resetToReadyState: false)

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

    func updateMovementControl(_ vector: MovementControlVector) {
        guard movementControlSupportedForSelection else {
            movementControlVector = .zero
            statusMessage = .localized(TeleportStrings.movementAvailableForSimulatorOnly)
            return
        }

        guard movementControlAvailable else {
            movementControlVector = .zero
            statusMessage = .localized(TeleportStrings.movementRequiresConnection)
            return
        }

        guard !vector.isZero else {
            stopMovementControl()
            return
        }

        guard currentMovementAnchorCoordinate != nil else {
            movementControlVector = .zero
            statusMessage = .localized(TeleportStrings.movementRequiresValidCoordinates)
            return
        }

        suppressPickedLocationPin = true
        movementControlVector = vector

        guard movementLoopTask == nil else {
            return
        }

        movementLoopTask = Task {
            await runMovementLoop()
        }
    }

    func stopMovementControl(commitCurrentCoordinateToTextFields: Bool = true) {
        movementControlVector = .zero
        movementLoopTask?.cancel()
        movementLoopTask = nil

        guard commitCurrentCoordinateToTextFields,
            case .simulating(let coordinate) = simulationState
        else {
            return
        }

        latitudeText = String(format: "%.6f", coordinate.latitude)
        longitudeText = String(format: "%.6f", coordinate.longitude)
    }

    func prepareForTermination() async {
        stopMovementControl(commitCurrentCoordinateToTextFields: false)
        stopRoutePlayback(resetToReadyState: false)
        TeleportLog.devices.info("Preparing services for application termination")
        await registry.shutdownAll()
        connectionState = .disconnected
        simulationState = .idle
        statusMessage = .localized(TeleportStrings.disconnectedAndClearedLocations)
        TeleportLog.devices.info("All services shut down for termination")
    }

    func dismissPythonDependencyGuide() {
        showsPythonDependencyGuide = nil
    }

    private func handleSimulationError(_ error: Error) {
        stopMovementControl(commitCurrentCoordinateToTextFields: false)
        let message = error.localizedDescription
        TeleportLog.simulation.error("Simulation failed: \(message, privacy: .public)")

        if let guide = PythonDependencyInstallGuide.parse(from: message) {
            showsPythonDependencyGuide = guide
            simulationState = .failed(.localized(TeleportStrings.missingPythonDependency))
            statusMessage = .localized(TeleportStrings.installPythonDependency)
            return
        }

        let userFacingMessage = UserFacingText.verbatim(message)
        simulationState = .failed(userFacingMessage)
        statusMessage = userFacingMessage
    }

    private func handleRoutePlaybackError(_ error: Error) {
        routePlaybackTask?.cancel()
        routePlaybackTask = nil

        let message = UserFacingText.verbatim(error.localizedDescription)
        routePlaybackState = .failed(message)
        statusMessage = message
        TeleportLog.simulation.error("Route playback failed: \(error.localizedDescription, privacy: .public)")
    }

    func updateSelectedPythonRuntimeNote() async {
        guard selectedDevice?.kind.isPhysicalDevice == true,
            let usbService = registry.service(for: .physicalUSB) as? USBDeviceLocationService,
            let path = await usbService.resolvedPythonExecutablePathForDisplay()
        else {
            selectedUSBSetupGuide =
                selectedDevice?.kind.isPhysicalDevice == true ? USBSetupGuide(resolvedPythonPath: nil) : nil
            selectedPythonRuntimeNote = nil
            if selectedDevice?.kind.isPhysicalDevice == true {
                TeleportLog.devices.debug("No resolved Python executable available for the selected physical device")
            }
            return
        }

        selectedUSBSetupGuide = USBSetupGuide(resolvedPythonPath: path)
        selectedPythonRuntimeNote = .localized(TeleportStrings.usbHelperPython(path))
        TeleportLog.devices.debug("Resolved physical-device helper Python executable at \(path, privacy: .public)")
    }

    private func beginSimulationAction(kind: StaticString) -> Bool {
        guard !isSimulationActionInFlight else {
            TeleportLog.simulation.debug(
                "Ignoring duplicate simulation control request while another control action is in progress: \(kind)"
            )
            return false
        }

        isSimulationActionInFlight = true
        return true
    }

    private enum ActionStateTarget {
        case connection
        case simulation
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
        let displayedCoordinate = route.waypoints.indices.contains(clampedIndex)
            ? ChinaCoordinateTransform.displayCoordinate(for: route.waypoints[clampedIndex].coordinate)
            : nil

        let traveledDistanceMeters: Double
        if clampedIndex > 0 {
            traveledDistanceMeters = zip(route.waypoints.prefix(clampedIndex), route.waypoints.dropFirst().prefix(clampedIndex))
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
        let timeStepCount = totalDelaySeconds > 0
            ? max(1, Int(ceil(totalDelaySeconds / routePlaybackSmoothingIntervalSeconds)))
            : 1
        let distanceStepCount = segmentDistanceMeters > 0
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

    private var currentMovementAnchorCoordinate: LocationCoordinate? {
        if case .simulating(let coordinate) = simulationState {
            return coordinate
        }

        guard let latitude = Double(latitudeText),
            let longitude = Double(longitudeText),
            (-90.0...90.0).contains(latitude),
            (-180.0...180.0).contains(longitude)
        else {
            return nil
        }

        return LocationCoordinate(latitude: latitude, longitude: longitude)
    }

    private func runMovementLoop() async {
        guard let device = selectedDevice,
            let service = registry.service(for: device.kind),
            movementControlAvailable,
            movementControlSupportedForSelection,
            var coordinate = currentMovementAnchorCoordinate
        else {
            movementLoopTask = nil
            movementControlVector = .zero
            return
        }

        TeleportLog.simulation.info(
            "Starting movement loop on \(device.logLabel, privacy: .public) at \(coordinate.formatted, privacy: .private)"
        )

        defer {
            movementLoopTask = nil
            movementControlVector = .zero
        }

        do {
            if case .simulating = simulationState {
                // Keep the active simulated location as the movement origin.
            } else {
                try await applyDisplayedSimulationCoordinate(coordinate, on: device, using: service)
            }

            var lastStepStartedAt = Date()

            while !Task.isCancelled {
                let vector = movementControlVector
                guard !vector.isZero else {
                    break
                }

                let stepStartedAt = Date()
                let direction = vector.normalized
                let elapsedSinceLastStep = max(
                    stepStartedAt.timeIntervalSince(lastStepStartedAt),
                    movementTickIntervalSeconds
                )
                lastStepStartedAt = stepStartedAt
                let effectiveSpeed = movementSpeedMetersPerSecond * vector.magnitude
                let stepDistance = effectiveSpeed * elapsedSinceLastStep
                coordinate = coordinate.offsetBy(
                    northMeters: -direction.y * stepDistance,
                    eastMeters: direction.x * stepDistance
                )

                try await applyDisplayedSimulationCoordinate(
                    coordinate,
                    on: device,
                    using: service,
                    moving: true
                )

                let remainingDelay = movementTickIntervalSeconds - Date().timeIntervalSince(stepStartedAt)
                if remainingDelay > 0 {
                    try await Task.sleep(
                        nanoseconds: UInt64(remainingDelay * 1_000_000_000)
                    )
                }
            }

            TeleportLog.simulation.info(
                "Stopped movement loop on \(device.logLabel, privacy: .public) at \(coordinate.formatted, privacy: .private)"
            )
        } catch is CancellationError {
            TeleportLog.simulation.debug("Movement loop cancelled")
        } catch {
            handleSimulationError(error)
        }
    }

    private func applyDisplayedSimulationCoordinate(
        _ coordinate: LocationCoordinate,
        on device: Device,
        using service: LocationSimulationService,
        moving: Bool = false
    ) async throws {
        let simulationCoordinate = ChinaCoordinateTransform.simulationCoordinate(fromDisplayed: coordinate)

        try await service.setLocation(simulationCoordinate)
        simulationState = .simulating(coordinate)
        showsPythonDependencyGuide = nil
        statusMessage =
            moving
            ? .localized(TeleportStrings.movingCoordinate(coordinate.formatted, on: device.name))
            : .localized(TeleportStrings.simulatingCoordinate(coordinate.formatted, on: device.name))

        if !moving {
            TeleportLog.simulation.info(
                "Simulation active on \(device.logLabel, privacy: .public); displayed coordinate: \(coordinate.formatted, privacy: .private)"
            )
        }
    }

    private func refreshedDeviceForAction(_ device: Device, stateTarget: ActionStateTarget) async -> Device? {
        guard device.kind.isPhysicalDevice else {
            return device
        }

        guard let service = registry.service(for: .physicalUSB) else {
            return device
        }

        do {
            let refreshedUSBDevices = try await service.discoverDevices()
            let nonUSBDevices = devices.filter { !$0.kind.isPhysicalDevice }
            if let refreshedDevice = refreshedUSBDevices.first(where: { $0.id == device.id }),
                refreshedDevice.isAvailable
            {
                devices = (nonUSBDevices + refreshedUSBDevices).sorted { $0.name < $1.name }
                selectedDeviceID = device.id
                return refreshedDevice
            }

            let unavailableDevice = unavailableVersion(
                of: refreshedUSBDevices.first(where: { $0.id == device.id }) ?? device
            )
            let mergedUSBDevices =
                refreshedUSBDevices
                .filter { $0.id != unavailableDevice.id }
                + [unavailableDevice]

            devices = (nonUSBDevices + mergedUSBDevices).sorted { $0.name < $1.name }
            selectedDeviceID = unavailableDevice.id

            await invalidateDisconnectedUSBDevice(unavailableDevice, stateTarget: stateTarget)
            return nil
        } catch {
            TeleportLog.devices.error(
                "Failed to revalidate USB device \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return device
        }
    }

    private func unavailableVersion(of device: Device) -> Device {
        Device(
            id: device.id,
            name: device.name,
            kind: device.kind,
            osVersion: device.osVersion,
            isAvailable: false,
            details: String(
                localized: device.kind == .physicalNetwork
                    ? TeleportStrings.wifiDeviceUnavailableDetails
                    : TeleportStrings.usbDeviceUnavailableDetails
            )
        )
    }

    private func invalidateDisconnectedUSBDevice(_ device: Device, stateTarget: ActionStateTarget) async {
        let message = UserFacingText.localized(TeleportStrings.selectedPhysicalDeviceUnavailable)

        if let service = registry.service(for: .physicalUSB) {
            await service.disconnect()
        }

        connectionState = .failed(message)
        simulationState = .idle
        showsPythonDependencyGuide = nil
        statusMessage = message

        switch stateTarget {
        case .connection:
            TeleportLog.devices.warning(
                "Physical device \(device.logLabel, privacy: .public) became unavailable before connect"
            )
        case .simulation:
            simulationState = .failed(message)
            TeleportLog.simulation.warning(
                "Physical device \(device.logLabel, privacy: .public) became unavailable before simulation action"
            )
        }
    }
}
