import Foundation
import OSLog

actor USBDeviceLocationService: LocationSimulationService {
    let kind: DeviceKind = .physicalUSB

    private let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    private let sudoURL = URL(fileURLWithPath: "/usr/bin/sudo")
    private let shellURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")

    private var connectedDevice: Device?
    private var activeCoordinate: LocationCoordinate?
    private var simulationHelper: USBSimulationHelper?
    private var resolvedPythonExecutableURL: URL?

    func discoverDevices() async throws -> [Device] {
        TeleportLog.devices.info("Discovering connected physical USB devices")
        let xcdeviceOutput = try CommandRunner.run(xcrunURL, arguments: ["xcdevice", "list"])
        let devices = try JSONDecoder().decode([XCDeviceRecord].self, from: xcdeviceOutput.stdout)
        let metadata = (try? loadCoreDeviceMetadata()) ?? [:]

        let discoveredDevices =
            devices
            .filter { !$0.simulator && $0.platform == "com.apple.platform.iphoneos" && $0.interface == "usb" }
            .map { device in
                let coreDevice = metadata[device.identifier]
                let developerMode = coreDevice?.deviceProperties.developerModeStatus ?? "unknown"
                let pairingState =
                    coreDevice?.connectionProperties.pairingState ?? (device.available ? "paired" : "unavailable")
                let isAvailable = resolvedAvailability(for: device, coreDevice: coreDevice)
                let details =
                    isAvailable
                    ? "USB · \(pairingState) · dev mode \(developerMode)"
                    : String(localized: TeleportStrings.usbDeviceUnavailableDetails)

                return Device(
                    id: device.identifier,
                    name: device.name,
                    kind: .physicalUSB,
                    osVersion: device.operatingSystemVersion,
                    isAvailable: isAvailable,
                    details: details
                )
            }
            .sorted { $0.name < $1.name }

        TeleportLog.devices.info("Discovered \(discoveredDevices.count) physical USB device(s)")
        return discoveredDevices
    }

    func resolvedPythonExecutablePathForDisplay() -> String? {
        try? resolvedPythonExecutable().path
    }

    func connect(to device: Device) async throws {
        guard device.isAvailable else {
            TeleportLog.devices.warning(
                "Attempted to connect to unavailable USB device \(device.logLabel, privacy: .public)"
            )
            throw ServiceError.unavailable(String(localized: TeleportStrings.selectedDeviceUnavailableOverUSB))
        }

        if connectedDevice?.id != device.id {
            if connectedDevice != nil {
                TeleportLog.devices.debug("Switching active USB device to \(device.logLabel, privacy: .public)")
            }
            try? await stopSimulationHelper()
            activeCoordinate = nil
        }

        connectedDevice = device
        TeleportLog.devices.info("USB device connected: \(device.logLabel, privacy: .public)")
    }

    func disconnect() async {
        if let connectedDevice {
            TeleportLog.devices.info("Disconnecting USB device \(connectedDevice.logLabel, privacy: .public)")
        }
        try? await stopSimulationHelper()
        connectedDevice = nil
        activeCoordinate = nil
    }

    func setLocation(_ coordinate: LocationCoordinate) async throws {
        guard let connectedDevice else {
            throw ServiceError.invalidSelection
        }

        TeleportLog.simulation.info(
            "Starting USB location simulation for \(connectedDevice.logLabel, privacy: .public) at \(coordinate.formatted, privacy: .private)"
        )
        try? await stopSimulationHelper()

        let helper = try makeSimulationHelper(mode: "set", device: connectedDevice, coordinate: coordinate)

        do {
            try helper.process.run()
            TeleportLog.simulation.debug(
                "Launched USB simulation helper for \(connectedDevice.logLabel, privacy: .public)")
        } catch {
            helper.cleanup()
            TeleportLog.simulation.error(
                "Failed to launch USB simulation helper for \(connectedDevice.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw ServiceError.unavailable(
                String(localized: TeleportStrings.failedToLaunchPhysicalDeviceHelper(error.localizedDescription))
            )
        }

        do {
            try await waitForHelperReady(helper)
        } catch {
            if helper.process.isRunning {
                helper.process.terminate()
                helper.process.waitUntilExit()
            }
            helper.cleanup()
            TeleportLog.simulation.error(
                "USB simulation helper failed to become ready for \(connectedDevice.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }

        simulationHelper = helper
        activeCoordinate = coordinate
        TeleportLog.simulation.info("USB simulation active for \(connectedDevice.logLabel, privacy: .public)")
    }

    func clearLocation() async throws {
        guard let connectedDevice else {
            throw ServiceError.invalidSelection
        }

        TeleportLog.simulation.info("Clearing USB simulated location for \(connectedDevice.logLabel, privacy: .public)")
        if simulationHelper != nil {
            try await stopSimulationHelper()
            activeCoordinate = nil
            TeleportLog.simulation.info(
                "Stopped active USB simulation helper for \(connectedDevice.logLabel, privacy: .public)")
            return
        }

        try runOneShotHelper(mode: "clear", device: connectedDevice, coordinate: nil)
        activeCoordinate = nil
        TeleportLog.simulation.info("Cleared USB simulated location for \(connectedDevice.logLabel, privacy: .public)")
    }

    private func loadCoreDeviceMetadata() throws -> [String: CoreDeviceRecord] {
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("teleport-devicectl.json")

        TeleportLog.devices.debug("Loading CoreDevice metadata for USB device discovery")
        _ = try CommandRunner.run(
            xcrunURL,
            arguments: ["devicectl", "list", "devices", "--json-output", outputURL.path]
        )

        let data = try Data(contentsOf: outputURL)
        let response = try JSONDecoder().decode(CoreDeviceListResponse.self, from: data)
        return Dictionary(uniqueKeysWithValues: response.result.devices.map { ($0.hardwareProperties.udid, $0) })
    }

    private func resolvedAvailability(for device: XCDeviceRecord, coreDevice: CoreDeviceRecord?) -> Bool {
        guard device.available else {
            if let coreDevice {
                TeleportLog.devices.debug(
                    "Treating USB device \(device.name, privacy: .public) as unavailable; xcdevice available=false, pairing=\(coreDevice.connectionProperties.pairingState, privacy: .public), developer mode=\(coreDevice.deviceProperties.developerModeStatus, privacy: .public)"
                )
            }
            return false
        }

        return true
    }

    private func resolvedPythonExecutable() throws -> URL {
        if let resolvedPythonExecutableURL {
            return resolvedPythonExecutableURL
        }

        TeleportLog.devices.debug("Resolving python3 executable for USB helper")
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
        TeleportLog.devices.info("Resolved python3 executable for USB helper at \(path, privacy: .public)")
        return resolvedURL
    }

    private func makeSimulationHelper(
        mode: String,
        device: Device,
        coordinate: LocationCoordinate?
    ) throws -> USBSimulationHelper {
        let helperFiles = try USBDeviceScript.makeHelperFiles()
        let pythonExecutableURL = try resolvedPythonExecutable()
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = sudoURL
        process.arguments =
            ["-A", pythonExecutableURL.path]
            + USBDeviceScript.helperArguments(
                mode: mode,
                device: device,
                coordinate: coordinate,
                statusURL: helperFiles.statusURL
            )
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "SUDO_ASKPASS": helperFiles.askpassScriptURL.path,
                "SUDO_PROMPT": USBDeviceScript.sudoPrompt
            ],
            uniquingKeysWith: { _, new in new }
        )

        return USBSimulationHelper(
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe,
            stderr: stderrPipe,
            statusURL: helperFiles.statusURL,
            askpassScriptURL: helperFiles.askpassScriptURL
        )
    }

    private func runOneShotHelper(mode: String, device: Device, coordinate: LocationCoordinate?) throws {
        TeleportLog.simulation.debug(
            "Running one-shot USB helper in \(mode, privacy: .public) mode for \(device.logLabel, privacy: .public)"
        )
        let helper = try makeSimulationHelper(mode: mode, device: device, coordinate: coordinate)

        do {
            try helper.process.run()
        } catch {
            helper.cleanup()
            TeleportLog.simulation.error(
                "Failed to launch one-shot USB helper for \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
                "One-shot USB helper failed for \(device.logLabel, privacy: .public) with exit code \(helper.process.terminationStatus)"
            )
            throw USBDeviceErrorParser.helperFailure(
                stdout: stdout,
                stderr: stderr,
                fallback: String(localized: TeleportStrings.failedToClearPhysicalDeviceLocation)
            )
        }

        TeleportLog.simulation.debug(
            "One-shot USB helper completed in \(mode, privacy: .public) mode for \(device.logLabel, privacy: .public)"
        )
    }

    private func stopSimulationHelper() async throws {
        guard let simulationHelper else {
            return
        }

        TeleportLog.simulation.debug("Stopping active USB simulation helper")
        self.simulationHelper = nil
        simulationHelper.stdin.closeFile()
        await USBDeviceProcessSupport.waitForProcessExit(simulationHelper.process, timeoutNanoseconds: 5_000_000_000)

        if simulationHelper.process.isRunning {
            simulationHelper.process.terminate()
            simulationHelper.process.waitUntilExit()
        }

        let stdout = simulationHelper.stdout.fileHandleForReading.readDataToEndOfFile()
        let stderr = simulationHelper.stderr.fileHandleForReading.readDataToEndOfFile()
        simulationHelper.cleanup()

        guard simulationHelper.process.terminationStatus == 0 else {
            TeleportLog.simulation.error(
                "USB simulation helper exited with code \(simulationHelper.process.terminationStatus) while stopping"
            )
            throw USBDeviceErrorParser.helperFailure(
                stdout: stdout,
                stderr: stderr,
                fallback: "Failed to clear the physical-device simulated location."
            )
        }

        TeleportLog.simulation.debug("USB simulation helper stopped cleanly")
    }

    private func waitForHelperReady(_ helper: USBSimulationHelper) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 30_000_000_000

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if FileManager.default.fileExists(atPath: helper.statusURL.path) {
                let status = (try? String(contentsOf: helper.statusURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard status == "READY" else {
                    TeleportLog.simulation.error(
                        "USB simulation helper reported invalid startup state: \(status ?? "<nil>", privacy: .public)"
                    )
                    throw ServiceError.unavailable(
                        status ?? String(localized: TeleportStrings.physicalHelperInvalidStartupState))
                }

                TeleportLog.simulation.debug("USB simulation helper reported ready")
                return
            }

            if !helper.process.isRunning {
                TeleportLog.simulation.error("USB simulation helper exited before reporting ready")
                throw USBDeviceErrorParser.helperFailure(
                    stdout: helper.stdout.fileHandleForReading.readDataToEndOfFile(),
                    stderr: helper.stderr.fileHandleForReading.readDataToEndOfFile(),
                    fallback: String(localized: TeleportStrings.physicalHelperExitedBeforeReady)
                )
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        TeleportLog.simulation.error("Timed out waiting for USB simulation helper readiness")
        throw ServiceError.unavailable(
            String(localized: TeleportStrings.timedOutWaitingForAdministratorApproval)
        )
    }
}
