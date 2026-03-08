import Foundation
import OSLog

extension AppViewModel {
    var selectedDevice: Device? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var selectedDeviceRequiresAdministratorApproval: Bool {
        selectedDevice?.kind == .physicalUSB
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
        TeleportLog.devices.info("Starting device discovery across simulator and USB services")
        discoveryState = .discovering
        statusMessage = "Scanning for simulator and USB devices..."

        do {
            async let simulatorDevices = registry.service(for: .simulator)?.discoverDevices() ?? []
            async let physicalDevices = registry.service(for: .physicalUSB)?.discoverDevices() ?? []
            let discovered = try await simulatorDevices + physicalDevices
            devices = discovered.sorted { $0.name < $1.name }
            selectedDeviceID = devices.first?.id
            await updateSelectedPythonRuntimeNote()
            discoveryState = .ready
            statusMessage = devices.isEmpty ? "No devices found." : "Found \(devices.count) device(s)."
            TeleportLog.devices.info(
                "Device discovery completed with \(self.devices.count) device(s); selected device: \(self.selectedDevice?.logLabel ?? "none", privacy: .public)"
            )
        } catch {
            discoveryState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            TeleportLog.devices.error(
                "Device discovery failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func connectSelectedDevice() async {
        guard let device = selectedDevice else {
            connectionState = .failed(ServiceError.invalidSelection.localizedDescription)
            TeleportLog.devices.warning("Connect requested without a selected device")
            return
        }
        guard let service = registry.service(for: device.kind) else {
            connectionState = .failed(
                ServiceError.unsupported("No service available for \(device.kind.rawValue).").localizedDescription)
            TeleportLog.devices.error(
                "No service available while connecting to \(device.logLabel, privacy: .public)"
            )
            return
        }

        TeleportLog.devices.info("Connecting to \(device.logLabel, privacy: .public)")
        connectionState = .connecting
        statusMessage = "Connecting to \(device.name)..."

        do {
            try await service.connect(to: device)
            connectionState = .connected
            statusMessage = "Connected to \(device.name)."
            TeleportLog.devices.info("Connected to \(device.logLabel, privacy: .public)")
        } catch {
            connectionState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            TeleportLog.devices.error(
                "Connection failed for \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func disconnectSelectedDevice() async {
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
        statusMessage = "Disconnected from \(device.name)."
        TeleportLog.devices.info("Disconnected from \(device.logLabel, privacy: .public)")
    }

    func simulateSelectedLocation() async {
        guard let device = selectedDevice else {
            simulationState = .failed(ServiceError.invalidSelection.localizedDescription)
            TeleportLog.simulation.warning("Simulation requested without a selected device")
            return
        }
        guard let service = registry.service(for: device.kind) else {
            simulationState = .failed(
                ServiceError.unsupported("No service available for \(device.kind.rawValue).").localizedDescription)
            TeleportLog.simulation.error(
                "No service available while simulating on \(device.logLabel, privacy: .public)"
            )
            return
        }
        guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else {
            simulationState = .failed("Enter valid coordinates.")
            statusMessage = "Enter valid coordinates."
            TeleportLog.simulation.warning(
                "Simulation rejected for \(device.logLabel, privacy: .public) because coordinates were invalid"
            )
            return
        }

        if device.kind == .physicalUSB && showsUSBApprovalReminder {
            showsUSBPrivilegeNotice = true
            statusMessage = "Review the administrator approval note to continue with USB location simulation."
            TeleportLog.simulation.info(
                "Showing administrator approval reminder before USB simulation for \(device.logLabel, privacy: .public)"
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
            if device.kind == .physicalUSB {
                simulationState = .authorizing
                statusMessage =
                    "Waiting for macOS administrator approval. Your password is entered in a separate system dialog and is never stored by Teleport."
                TeleportLog.simulation.info(
                    "Waiting for administrator authorization for USB simulation on \(device.logLabel, privacy: .public)"
                )
            }
            try await service.setLocation(simulationCoordinate)
            simulationState = .simulating(coordinate)
            showsPythonDependencyGuide = nil
            statusMessage = "Simulating \(coordinate.formatted) on \(device.name)."
            TeleportLog.simulation.info(
                "Simulation active on \(device.logLabel, privacy: .public); displayed coordinate: \(coordinate.formatted, privacy: .private)"
            )
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
        simulationState = .failed("Administrator approval was canceled before the macOS password prompt.")
        statusMessage = "Administrator approval was canceled before the macOS password prompt."
        TeleportLog.simulation.warning("Administrator approval reminder was dismissed before USB simulation")
    }

    func clearSimulatedLocation() async {
        guard let device = selectedDevice, let service = registry.service(for: device.kind) else {
            simulationState = .failed(ServiceError.invalidSelection.localizedDescription)
            TeleportLog.simulation.warning("Clear simulated location requested without a selected device")
            return
        }

        TeleportLog.simulation.info("Clearing simulated location on \(device.logLabel, privacy: .public)")
        simulationState = .stopping
        do {
            try await service.clearLocation()
            simulationState = .idle
            showsPythonDependencyGuide = nil
            statusMessage = "Cleared simulated location on \(device.name)."
            TeleportLog.simulation.info("Cleared simulated location on \(device.logLabel, privacy: .public)")
        } catch {
            handleSimulationError(error)
        }
    }

    func prepareForTermination() async {
        TeleportLog.devices.info("Preparing services for application termination")
        await registry.shutdownAll()
        connectionState = .disconnected
        simulationState = .idle
        statusMessage = "Disconnected and cleared simulated locations."
        TeleportLog.devices.info("All services shut down for termination")
    }

    func dismissPythonDependencyGuide() {
        showsPythonDependencyGuide = nil
    }

    private func handleSimulationError(_ error: Error) {
        let message = error.localizedDescription
        TeleportLog.simulation.error("Simulation failed: \(message, privacy: .public)")

        if let guide = PythonDependencyInstallGuide.parse(from: message) {
            showsPythonDependencyGuide = guide
            simulationState = .failed("Missing Python dependency")
            statusMessage =
                "Install pymobiledevice3 for the selected Python interpreter to continue USB location simulation."
            return
        }

        simulationState = .failed(message)
        statusMessage = message
    }

    func updateSelectedPythonRuntimeNote() async {
        guard selectedDevice?.kind == .physicalUSB,
            let usbService = registry.service(for: .physicalUSB) as? USBDeviceLocationService,
            let path = await usbService.resolvedPythonExecutablePathForDisplay()
        else {
            selectedUSBSetupGuide = selectedDevice?.kind == .physicalUSB ? USBSetupGuide(resolvedPythonPath: nil) : nil
            selectedPythonRuntimeNote = nil
            if selectedDevice?.kind == .physicalUSB {
                TeleportLog.devices.debug("No resolved Python executable available for the selected USB device")
            }
            return
        }

        selectedUSBSetupGuide = USBSetupGuide(resolvedPythonPath: path)
        selectedPythonRuntimeNote = "USB helper Python: \(path)"
        TeleportLog.devices.debug("Resolved USB helper Python executable at \(path, privacy: .public)")
    }
}