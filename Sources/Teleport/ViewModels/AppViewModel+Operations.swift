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

    func handleSimulationError(_ error: Error) {
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

    enum ActionStateTarget {
        case connection
        case simulation
    }

    func applyDisplayedSimulationCoordinate(
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

    func refreshedDeviceForAction(_ device: Device, stateTarget: ActionStateTarget) async -> Device? {
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
