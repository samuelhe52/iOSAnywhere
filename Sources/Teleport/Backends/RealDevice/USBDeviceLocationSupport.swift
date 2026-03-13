import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct USBSimulationHelper {
    let process: Process
    let stdin: FileHandle
    let stdout: Pipe
    let stderr: Pipe
    let statusURL: URL
    let stopURL: URL
    let promptScriptURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: statusURL)
        try? FileManager.default.removeItem(at: stopURL)
        try? FileManager.default.removeItem(at: promptScriptURL)
    }
}

enum USBDeviceProcessSupport {
    static func waitForProcessExit(_ process: Process, timeoutNanoseconds: UInt64) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while process.isRunning && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    static func requestTerminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        let processIdentifier = process.processIdentifier
        guard processIdentifier > 0 else {
            return
        }

        _ = kill(processIdentifier, SIGTERM)
    }

    static func forceTerminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        let processIdentifier = process.processIdentifier
        guard processIdentifier > 0 else {
            return
        }

        _ = kill(processIdentifier, SIGKILL)
    }
}

enum USBDeviceErrorParser {
    static func helperFailure(stdout: Data, stderr: Data, fallback: String) -> ServiceError {
        let stderrText = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let stdoutText = String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if let friendlyMessage = friendlyAuthorizationMessage(stderr: stderrText, stdout: stdoutText) {
            return ServiceError.unavailable(friendlyMessage)
        }

        if let dependencyGuidance = missingPythonDependencyMessage(stderr: stderrText, stdout: stdoutText) {
            return ServiceError.unavailable(dependencyGuidance)
        }

        let output = [stderrText, stdoutText].first(where: { !$0.isEmpty })
        return ServiceError.unavailable(output ?? fallback)
    }

    private static func friendlyAuthorizationMessage(stderr: String, stdout: String) -> String? {
        let combined = [stderr, stdout]
            .joined(separator: "\n")
            .lowercased()

        if combined.contains("__teleport_auth_cancelled__") {
            return String(localized: TeleportStrings.administratorApprovalCanceled)
        }

        if combined.contains("incorrect password")
            || combined.contains("sorry, try again")
            || combined.contains("incorrect password attempt")
        {
            return String(localized: TeleportStrings.administratorPasswordIncorrect)
        }

        if combined.contains("no password was provided")
            || (combined.contains("a password is required") && combined.contains("sudo"))
        {
            return String(localized: TeleportStrings.administratorApprovalCanceled)
        }

        return nil
    }

    private static func missingPythonDependencyMessage(stderr: String, stdout: String) -> String? {
        let combined = [stderr, stdout].joined(separator: "\n")

        guard combined.localizedCaseInsensitiveContains("pymobiledevice3 is not installed") else {
            return nil
        }

        let resolvedPython = extractValue(in: combined, prefix: "Resolved Python: ")
        let installCommand = extractValue(in: combined, prefix: "Install command: ")

        var lines = [String(localized: TeleportStrings.pythonDependencyMissingIntro)]

        if let resolvedPython {
            lines.append(String(localized: TeleportStrings.resolvedPythonLine(resolvedPython)))
        }

        if let installCommand {
            lines.append(String(localized: TeleportStrings.runCommandLine(installCommand)))
        }

        lines.append(String(localized: TeleportStrings.retryUSBLocationAction))
        return lines.joined(separator: "\n")
    }

    private static func extractValue(in text: String, prefix: String) -> String? {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                let line = String(line)
                guard line.hasPrefix(prefix) else {
                    return nil
                }

                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
    }
}

struct CoreDeviceListResponse: Decodable {
    let result: CoreDeviceResult
}

struct CoreDeviceResult: Decodable {
    let devices: [CoreDeviceRecord]
}

struct CoreDeviceRecord: Decodable {
    let capabilities: [CoreDeviceCapability]
    let connectionProperties: CoreDeviceConnectionProperties
    let deviceProperties: CoreDeviceProperties
    let hardwareProperties: CoreDeviceHardwareProperties
}

struct CoreDeviceCapability: Decodable {
    let featureIdentifier: String
}

struct CoreDeviceConnectionProperties: Decodable {
    let pairingState: String
    let transportType: String?
    let tunnelState: String?
    let tunnelTransportProtocol: String?
}

struct CoreDeviceProperties: Decodable {
    let ddiServicesAvailable: Bool?
    let developerModeStatus: String
    let bootState: String?
    let name: String
    let osBuildUpdate: String?
    let osVersionNumber: String
}

struct CoreDeviceHardwareProperties: Decodable {
    let platform: String
    let reality: String
    let udid: String
}
