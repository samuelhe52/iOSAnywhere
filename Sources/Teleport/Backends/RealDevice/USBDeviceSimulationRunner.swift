import Foundation
import OSLog

final class USBDeviceSimulationRunner {
    private let sudoURL: URL
    private let shellURL: URL

    private var simulationHelper: USBSimulationHelper?
    private var resolvedPythonExecutableURL: URL?

    init(
        sudoURL: URL = URL(fileURLWithPath: "/usr/bin/sudo"),
        shellURL: URL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    ) {
        self.sudoURL = sudoURL
        self.shellURL = shellURL
    }

    func resolvedPythonExecutablePathForDisplay() -> String? {
        try? resolvedPythonExecutable().path
    }

    func hasActiveSimulationSession() -> Bool {
        guard let simulationHelper else {
            return false
        }

        return simulationHelper.process.isRunning
    }

    func disconnect() async {
        try? await stopSimulationHelper()
    }

    func setLocation(_ coordinate: LocationCoordinate, on device: Device) async throws {
        if let simulationHelper {
            if simulationHelper.process.isRunning {
                TeleportLog.simulation.info(
                    "Updating physical-device location simulation for \(device.logLabel, privacy: .public) to \(coordinate.formatted, privacy: .private)"
                )
                do {
                    try sendCoordinateUpdate(coordinate, to: simulationHelper)
                    return
                } catch {
                    TeleportLog.simulation.error(
                        "Failed to stream coordinate update to physical-device helper for \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    try? await stopSimulationHelper()
                }
            } else {
                TeleportLog.simulation.warning(
                    "Physical-device helper was no longer running for \(device.logLabel, privacy: .public); starting a new session"
                )
                try? await stopSimulationHelper()
            }
        }

        TeleportLog.simulation.info(
            "Starting physical-device location simulation for \(device.logLabel, privacy: .public) at \(coordinate.formatted, privacy: .private)"
        )

        let (helper, administratorPassword) = try makeSimulationHelper(
            mode: "set",
            device: device,
            coordinate: coordinate
        )

        do {
            try helper.process.run()
            if let administratorPassword {
                try helper.stdin.write(contentsOf: Data((administratorPassword + "\n").utf8))
            }
            TeleportLog.simulation.debug(
                "Launched physical-device simulation helper for \(device.logLabel, privacy: .public)")
        } catch {
            helper.cleanup()
            TeleportLog.simulation.error(
                "Failed to launch physical-device simulation helper for \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
                "Physical-device simulation helper failed to become ready for \(device.logLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
        TeleportLog.simulation.info(
            "Physical-device simulation active for \(device.logLabel, privacy: .public)")
    }

    func clearLocation(on device: Device) async throws {
        TeleportLog.simulation.info(
            "Clearing physical-device simulated location for \(device.logLabel, privacy: .public)")
        if simulationHelper != nil {
            try await stopSimulationHelper()
            TeleportLog.simulation.info(
                "Stopped active physical-device simulation helper for \(device.logLabel, privacy: .public)")
            return
        }

        try runOneShotHelper(mode: "clear", device: device, coordinate: nil)
        TeleportLog.simulation.info(
            "Cleared physical-device simulated location for \(device.logLabel, privacy: .public)")
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
            await USBDeviceProcessSupport.waitForProcessExit(
                simulationHelper.process, timeoutNanoseconds: 1_000_000_000)
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
}
