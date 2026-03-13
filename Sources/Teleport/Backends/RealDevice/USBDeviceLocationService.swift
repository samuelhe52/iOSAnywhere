import Foundation
import OSLog

actor USBDeviceLocationService: LocationSimulationService {
    let supportedKinds: [DeviceKind] = [.physicalUSB, .physicalNetwork]

    private let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    private let sudoURL = URL(fileURLWithPath: "/usr/bin/sudo")
    private let shellURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")

    private var connectedDevice: Device?
    private var activeCoordinate: LocationCoordinate?
    private var simulationHelper: USBSimulationHelper?
    private var resolvedPythonExecutableURL: URL?

    func discoverDevices() async throws -> [Device] {
        TeleportLog.devices.info("Discovering physical devices from CoreDevice")
        let devices = try loadCoreDeviceDevices()

        let discoveredDevices: [Device] =
            devices
            .filter { (device: CoreDeviceRecord) in
                device.hardwareProperties.platform == "iOS" && device.hardwareProperties.reality == "physical"
            }
            .map { (device: CoreDeviceRecord) in
                let kind = physicalDeviceKind(for: device)
                let isAvailable = resolvedAvailability(for: device)
                let details =
                    isAvailable
                    ? availableDetails(for: device, kind: kind)
                    : unavailableDetails(for: kind)

                return Device(
                    id: device.hardwareProperties.udid,
                    name: device.deviceProperties.name,
                    kind: kind,
                    osVersion: formattedOSVersion(for: device),
                    isAvailable: isAvailable,
                    details: details
                )
            }
            .sorted { $0.name < $1.name }

        TeleportLog.devices.info("Discovered \(discoveredDevices.count) physical device(s)")
        return discoveredDevices
    }

    func resolvedPythonExecutablePathForDisplay() -> String? {
        try? resolvedPythonExecutable().path
    }

    func connect(to device: Device) async throws {
        guard device.isAvailable else {
            TeleportLog.devices.warning(
                "Attempted to connect to unavailable physical device \(device.logLabel, privacy: .public)"
            )
            throw ServiceError.unavailable(String(localized: TeleportStrings.selectedPhysicalDeviceUnavailable))
        }

        if connectedDevice?.id != device.id {
            if connectedDevice != nil {
                TeleportLog.devices.debug("Switching active physical device to \(device.logLabel, privacy: .public)")
            }
            try? await stopSimulationHelper()
            activeCoordinate = nil
        }

        connectedDevice = device
        TeleportLog.devices.info("Physical device connected: \(device.logLabel, privacy: .public)")
    }

    func disconnect() async {
        if let connectedDevice {
            TeleportLog.devices.info("Disconnecting physical device \(connectedDevice.logLabel, privacy: .public)")
        }
        try? await stopSimulationHelper()
        connectedDevice = nil
        activeCoordinate = nil
    }

    func hasActiveSimulationSession() async -> Bool {
        guard let simulationHelper else {
            return false
        }

        return simulationHelper.process.isRunning
    }

    func setLocation(_ coordinate: LocationCoordinate) async throws {
        guard let connectedDevice else {
            throw ServiceError.invalidSelection
        }

        if let simulationHelper {
            if simulationHelper.process.isRunning {
                TeleportLog.simulation.info(
                    "Updating physical-device location simulation for \(connectedDevice.logLabel, privacy: .public) to \(coordinate.formatted, privacy: .private)"
                )
                do {
                    try sendCoordinateUpdate(coordinate, to: simulationHelper)
                    activeCoordinate = coordinate
                    return
                } catch {
                    TeleportLog.simulation.error(
                        "Failed to stream coordinate update to physical-device helper for \(connectedDevice.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    try? await stopSimulationHelper()
                }
            } else {
                TeleportLog.simulation.warning(
                    "Physical-device helper was no longer running for \(connectedDevice.logLabel, privacy: .public); starting a new session"
                )
                try? await stopSimulationHelper()
            }
        }

        TeleportLog.simulation.info(
            "Starting physical-device location simulation for \(connectedDevice.logLabel, privacy: .public) at \(coordinate.formatted, privacy: .private)"
        )

        let (helper, administratorPassword) = try makeSimulationHelper(
            mode: "set",
            device: connectedDevice,
            coordinate: coordinate
        )

        do {
            try helper.process.run()
            if let administratorPassword {
                try helper.stdin.write(contentsOf: Data((administratorPassword + "\n").utf8))
            }
            TeleportLog.simulation.debug(
                "Launched physical-device simulation helper for \(connectedDevice.logLabel, privacy: .public)")
        } catch {
            helper.cleanup()
            TeleportLog.simulation.error(
                "Failed to launch physical-device simulation helper for \(connectedDevice.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw ServiceError.unavailable(
                String(localized: TeleportStrings.failedToLaunchPhysicalDeviceHelper(error.localizedDescription))
            )
        }

        do {
            try await waitForHelperReady(helper)
        } catch {
            if helper.process.isRunning {
                USBDeviceProcessSupport.requestTerminate(helper.process)
                await USBDeviceProcessSupport.waitForProcessExit(helper.process, timeoutNanoseconds: 1_000_000_000)
                if helper.process.isRunning {
                    USBDeviceProcessSupport.forceTerminate(helper.process)
                    helper.process.waitUntilExit()
                }
            }
            let stdout = helper.stdout.fileHandleForReading.readDataToEndOfFile()
            let stderr = helper.stderr.fileHandleForReading.readDataToEndOfFile()
            helper.cleanup()
            TeleportLog.simulation.error(
                "Physical-device simulation helper failed to become ready for \(connectedDevice.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            if !stdout.isEmpty || !stderr.isEmpty {
                throw USBDeviceErrorParser.helperFailure(
                    stdout: stdout,
                    stderr: stderr,
                    fallback: error.localizedDescription
                )
            }
            throw error
        }

        simulationHelper = helper
        activeCoordinate = coordinate
        TeleportLog.simulation.info(
            "Physical-device simulation active for \(connectedDevice.logLabel, privacy: .public)")
    }

    func clearLocation() async throws {
        guard let connectedDevice else {
            throw ServiceError.invalidSelection
        }

        TeleportLog.simulation.info(
            "Clearing physical-device simulated location for \(connectedDevice.logLabel, privacy: .public)")
        if simulationHelper != nil {
            try await stopSimulationHelper()
            activeCoordinate = nil
            TeleportLog.simulation.info(
                "Stopped active physical-device simulation helper for \(connectedDevice.logLabel, privacy: .public)")
            return
        }

        try runOneShotHelper(mode: "clear", device: connectedDevice, coordinate: nil)
        activeCoordinate = nil
        TeleportLog.simulation.info(
            "Cleared physical-device simulated location for \(connectedDevice.logLabel, privacy: .public)")
    }

    private func loadCoreDeviceDevices() throws -> [CoreDeviceRecord] {
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("teleport-devicectl.json")

        TeleportLog.devices.debug("Loading CoreDevice metadata for physical-device discovery")
        _ = try CommandRunner.run(
            xcrunURL,
            arguments: ["devicectl", "list", "devices", "--json-output", outputURL.path]
        )

        let data = try Data(contentsOf: outputURL)
        let response = try JSONDecoder().decode(CoreDeviceListResponse.self, from: data)
        return response.result.devices
    }

    private func resolvedAvailability(for device: CoreDeviceRecord) -> Bool {
        let isAvailable =
            device.connectionProperties.pairingState == "paired"
            && device.deviceProperties.developerModeStatus == "enabled"

        TeleportLog.devices.debug(
            "Resolved physical-device availability for \(device.deviceProperties.name, privacy: .public); transport=\(device.connectionProperties.transportType ?? "<nil>", privacy: .public), tunnelState=\(device.connectionProperties.tunnelState ?? "<nil>", privacy: .public), pairing=\(device.connectionProperties.pairingState, privacy: .public), developer mode=\(device.deviceProperties.developerModeStatus, privacy: .public), ddiServices=\(device.deviceProperties.ddiServicesAvailable ?? false, privacy: .public), available=\(isAvailable, privacy: .public)"
        )

        return isAvailable
    }

    private func resolvedPythonExecutable() throws -> URL {
        if let resolvedPythonExecutableURL {
            return resolvedPythonExecutableURL
        }

        TeleportLog.devices.debug("Resolving python3 executable for the physical-device helper")
        let output = try CommandRunner.run(
            shellURL,
            arguments: ["-lc", USBDeviceScript.pythonResolutionCommand]
        )
        let path = output.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard path.hasPrefix("/") else {
            throw ServiceError.unavailable(
                String(localized: TeleportStrings.unableToResolvePython3(from: shellURL.lastPathComponent))
            )
        }

        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw ServiceError.unavailable(String(localized: TeleportStrings.pythonPathNotExecutable(path)))
        }

        let resolvedURL = URL(fileURLWithPath: path)
        resolvedPythonExecutableURL = resolvedURL
        TeleportLog.devices.info(
            "Resolved python3 executable for the physical-device helper at \(path, privacy: .public)")
        return resolvedURL
    }

    private func makeSimulationHelper(
        mode: String,
        device: Device,
        coordinate: LocationCoordinate?
    ) throws -> (helper: USBSimulationHelper, administratorPassword: String?) {
        let helperFiles = try USBDeviceScript.makeHelperFiles()
        let pythonExecutableURL = try resolvedPythonExecutable()
        let administratorPassword = try administratorPasswordIfNeeded(using: helperFiles.promptScriptURL)
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = sudoURL
        process.arguments =
            ["-S", "-p", "", pythonExecutableURL.path]
            + USBDeviceScript.helperArguments(
                mode: mode,
                device: device,
                coordinate: coordinate,
                statusURL: helperFiles.statusURL,
                stopURL: helperFiles.stopURL
            )
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment

        return (
            helper: USBSimulationHelper(
                process: process,
                stdin: stdinPipe.fileHandleForWriting,
                stdout: stdoutPipe,
                stderr: stderrPipe,
                statusURL: helperFiles.statusURL,
                stopURL: helperFiles.stopURL,
                promptScriptURL: helperFiles.promptScriptURL
            ),
            administratorPassword: administratorPassword
        )
    }

    private func runOneShotHelper(mode: String, device: Device, coordinate: LocationCoordinate?) throws {
        TeleportLog.simulation.debug(
            "Running one-shot physical-device helper in \(mode, privacy: .public) mode for \(device.logLabel, privacy: .public)"
        )
        let (helper, administratorPassword) = try makeSimulationHelper(
            mode: mode, device: device, coordinate: coordinate)

        do {
            try helper.process.run()
            if let administratorPassword {
                try helper.stdin.write(contentsOf: Data((administratorPassword + "\n").utf8))
            }
            helper.stdin.closeFile()
        } catch {
            helper.cleanup()
            TeleportLog.simulation.error(
                "Failed to launch one-shot physical-device helper for \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw ServiceError.unavailable(
                String(localized: TeleportStrings.failedToLaunchPhysicalDeviceHelper(error.localizedDescription))
            )
        }

        helper.process.waitUntilExit()
        let stdout = helper.stdout.fileHandleForReading.readDataToEndOfFile()
        let stderr = helper.stderr.fileHandleForReading.readDataToEndOfFile()
        helper.cleanup()

        guard helper.process.terminationStatus == 0 else {
            TeleportLog.simulation.error(
                "One-shot physical-device helper failed for \(device.logLabel, privacy: .public) with exit code \(helper.process.terminationStatus)"
            )
            throw USBDeviceErrorParser.helperFailure(
                stdout: stdout,
                stderr: stderr,
                fallback: String(localized: TeleportStrings.failedToClearPhysicalDeviceLocation)
            )
        }

        TeleportLog.simulation.debug(
            "One-shot physical-device helper completed in \(mode, privacy: .public) mode for \(device.logLabel, privacy: .public)"
        )
    }

    private func sendCoordinateUpdate(_ coordinate: LocationCoordinate, to helper: USBSimulationHelper) throws {
        guard helper.process.isRunning else {
            throw ServiceError.unavailable(String(localized: TeleportStrings.physicalHelperExitedBeforeReady))
        }

        let command = "SET \(coordinate.latitude) \(coordinate.longitude)\n"
        try helper.stdin.write(contentsOf: Data(command.utf8))
    }

    private func stopSimulationHelper() async throws {
        guard let simulationHelper else {
            return
        }

        TeleportLog.simulation.debug("Stopping active physical-device simulation helper")
        self.simulationHelper = nil
        try? simulationHelper.stdin.write(contentsOf: Data("STOP\n".utf8))
        try? simulationHelper.stdin.close()
        FileManager.default.createFile(atPath: simulationHelper.stopURL.path, contents: Data(), attributes: nil)
        await USBDeviceProcessSupport.waitForProcessExit(simulationHelper.process, timeoutNanoseconds: 5_000_000_000)

        if simulationHelper.process.isRunning {
            USBDeviceProcessSupport.requestTerminate(simulationHelper.process)
            await USBDeviceProcessSupport.waitForProcessExit(simulationHelper.process, timeoutNanoseconds: 1_000_000_000)
        }

        if simulationHelper.process.isRunning {
            USBDeviceProcessSupport.forceTerminate(simulationHelper.process)
            simulationHelper.process.waitUntilExit()
        }

        let stdout = simulationHelper.stdout.fileHandleForReading.readDataToEndOfFile()
        let stderr = simulationHelper.stderr.fileHandleForReading.readDataToEndOfFile()
        simulationHelper.cleanup()

        guard simulationHelper.process.terminationStatus == 0 else {
            TeleportLog.simulation.error(
                "Physical-device simulation helper exited with code \(simulationHelper.process.terminationStatus) while stopping"
            )
            throw USBDeviceErrorParser.helperFailure(
                stdout: stdout,
                stderr: stderr,
                fallback: "Failed to clear the physical-device simulated location."
            )
        }

        TeleportLog.simulation.debug("Physical-device simulation helper stopped cleanly")
    }

    private func waitForHelperReady(_ helper: USBSimulationHelper) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 30_000_000_000
        var lastProgressStatus: String?

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if FileManager.default.fileExists(atPath: helper.statusURL.path) {
                let status = (try? String(contentsOf: helper.statusURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if status == "READY" {
                    TeleportLog.simulation.debug("Physical-device simulation helper reported ready")
                    return
                }

                if status != lastProgressStatus {
                    lastProgressStatus = status
                    TeleportLog.simulation.debug(
                        "Physical-device simulation helper startup progress for \(helper.statusURL.lastPathComponent, privacy: .private): \(status ?? "<nil>", privacy: .public)"
                    )
                }
            }

            if !helper.process.isRunning {
                TeleportLog.simulation.error("Physical-device simulation helper exited before reporting ready")
                throw USBDeviceErrorParser.helperFailure(
                    stdout: helper.stdout.fileHandleForReading.readDataToEndOfFile(),
                    stderr: helper.stderr.fileHandleForReading.readDataToEndOfFile(),
                    fallback: String(localized: TeleportStrings.physicalHelperExitedBeforeReady)
                )
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        TeleportLog.simulation.error(
            "Timed out waiting for physical-device simulation helper readiness; last progress state: \(lastProgressStatus ?? "<nil>", privacy: .public)"
        )
        throw ServiceError.unavailable(
            String(localized: TeleportStrings.timedOutWaitingForPhysicalDeviceStartup)
        )
    }

    private func promptForAdministratorPassword(using scriptURL: URL) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = scriptURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ServiceError.unavailable(
                String(localized: TeleportStrings.failedToLaunchPhysicalDeviceHelper(error.localizedDescription))
            )
        }

        process.waitUntilExit()

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            if stderr.localizedCaseInsensitiveContains("__teleport_auth_cancelled__") {
                throw ServiceError.unavailable(String(localized: TeleportStrings.administratorApprovalCanceled))
            }
            throw ServiceError.unavailable(String(localized: TeleportStrings.administratorApprovalCanceled))
        }

        guard !stdout.isEmpty else {
            throw ServiceError.unavailable(String(localized: TeleportStrings.administratorApprovalCanceled))
        }

        return stdout
    }

    private func administratorPasswordIfNeeded(using scriptURL: URL) throws -> String? {
        if try hasCachedAdministratorAuthorization() {
            TeleportLog.simulation.debug("Reusing cached sudo authorization for the physical-device helper")
            return nil
        }

        return try promptForAdministratorPassword(using: scriptURL)
    }

    private func hasCachedAdministratorAuthorization() throws -> Bool {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = sudoURL
        process.arguments = ["-n", "true"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ServiceError.unavailable(
                String(localized: TeleportStrings.failedToLaunchPhysicalDeviceHelper(error.localizedDescription))
            )
        }

        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func physicalDeviceKind(for device: CoreDeviceRecord) -> DeviceKind {
        switch device.connectionProperties.transportType?.lowercased() {
        case "localnetwork":
            return .physicalNetwork
        default:
            return .physicalUSB
        }
    }

    private func transportLabel(for kind: DeviceKind) -> String {
        switch kind {
        case .simulator:
            return "Simulator"
        case .physicalUSB:
            return "USB"
        case .physicalNetwork:
            return "Wi-Fi"
        }
    }

    private func unavailableDetails(for kind: DeviceKind) -> String {
        switch kind {
        case .simulator:
            return ""
        case .physicalUSB:
            return String(localized: TeleportStrings.usbDeviceUnavailableDetails)
        case .physicalNetwork:
            return String(localized: TeleportStrings.wifiDeviceUnavailableDetails)
        }
    }

    private func availableDetails(for device: CoreDeviceRecord, kind: DeviceKind) -> String {
        let pairingState = device.connectionProperties.pairingState
        let developerMode = device.deviceProperties.developerModeStatus
        let tunnelState = device.connectionProperties.tunnelState

        if let tunnelState, kind == .physicalNetwork {
            return "\(transportLabel(for: kind)) · \(pairingState) · tunnel \(tunnelState) · dev mode \(developerMode)"
        }

        return "\(transportLabel(for: kind)) · \(pairingState) · dev mode \(developerMode)"
    }

    private func formattedOSVersion(for device: CoreDeviceRecord) -> String {
        if let build = device.deviceProperties.osBuildUpdate {
            return "\(device.deviceProperties.osVersionNumber) (\(build))"
        }

        return device.deviceProperties.osVersionNumber
    }

}
