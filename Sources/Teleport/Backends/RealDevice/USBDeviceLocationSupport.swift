import Foundation

struct USBSimulationHelper {
    let process: Process
    let stdin: FileHandle
    let stdout: Pipe
    let stderr: Pipe
    let statusURL: URL
    let askpassScriptURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: statusURL)
        try? FileManager.default.removeItem(at: askpassScriptURL)
    }
}

enum USBDeviceProcessSupport {
    static func waitForProcessExit(_ process: Process, timeoutNanoseconds: UInt64) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while process.isRunning && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
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

        if combined.contains("incorrect password") || combined.contains("try again") {
            return String(localized: TeleportStrings.administratorPasswordIncorrect)
        }

        if combined.contains("no password was provided") || combined.contains("a password is required") {
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

enum USBDeviceScript {
    static var sudoPrompt: String {
        String(localized: TeleportStrings.usbSudoPrompt)
    }

    static let pythonResolutionCommand =
        #"python3 -c 'import os, sys; print(os.path.realpath(sys.executable))'"#

    static let pythonHelperScript = #"""
        import asyncio
        import re
        import shlex
        import sys


        def parse_version(version_text):
            parts = [int(part) for part in re.findall(r"\d+", version_text)[:2]]
            while len(parts) < 2:
                parts.append(0)
            return tuple(parts)


        def mark_ready(status_path):
            with open(status_path, "w", encoding="utf-8") as handle:
                handle.write("READY\n")


        async def hold_simulation(simulation):
            try:
                await asyncio.to_thread(sys.stdin.buffer.read)
            finally:
                await simulation.clear()


        async def run_pre_ios17(mode, udid, status_path, latitude, longitude):
            from pymobiledevice3.lockdown import create_using_usbmux
            from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

            lockdown = await create_using_usbmux(udid, autopair=True)
            try:
                async with DvtSecureSocketProxyService(lockdown) as dvt:
                    simulation = LocationSimulation(dvt)
                    await simulation.clear()
                    if mode == "set":
                        await simulation.set(latitude, longitude)
                        mark_ready(status_path)
                        await hold_simulation(simulation)
                    else:
                        await simulation.clear()
            finally:
                await lockdown.close()


        async def run_ios17_quic(mode, udid, status_path, latitude, longitude):
            from pymobiledevice3.bonjour import DEFAULT_BONJOUR_TIMEOUT
            from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
            from pymobiledevice3.remote.tunnel_service import get_remote_pairing_tunnel_services
            from pymobiledevice3.remote.utils import resume_remoted_if_required, stop_remoted_if_required
            from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

            stop_remoted_if_required()
            service_provider = None

            try:
                service_providers = await get_remote_pairing_tunnel_services(DEFAULT_BONJOUR_TIMEOUT, udid=udid)
                service_provider = service_providers[0] if service_providers else None
                if service_provider is None:
                    raise RuntimeError(f"No remote pairing tunnel service found for {udid}.")

                async with service_provider.start_quic_tunnel() as tunnel_result:
                    resume_remoted_if_required()
                    async with RemoteServiceDiscoveryService((tunnel_result.address, tunnel_result.port)) as rsd:
                        async with DvtSecureSocketProxyService(rsd) as dvt:
                            simulation = LocationSimulation(dvt)
                            await simulation.clear()
                            if mode == "set":
                                await simulation.set(latitude, longitude)
                                mark_ready(status_path)
                                await hold_simulation(simulation)
                            else:
                                await simulation.clear()
            finally:
                if service_provider is not None:
                    await service_provider.close()
                resume_remoted_if_required()


        async def run_ios17_tcp(mode, udid, status_path, latitude, longitude):
            from pymobiledevice3.lockdown import create_using_usbmux
            from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
            from pymobiledevice3.remote.tunnel_service import CoreDeviceTunnelProxy
            from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

            lockdown = await create_using_usbmux(udid, autopair=True)
            tunnel_proxy = await CoreDeviceTunnelProxy.create(lockdown)
            try:
                async with tunnel_proxy.start_tcp_tunnel() as tunnel_result:
                    async with RemoteServiceDiscoveryService((tunnel_result.address, tunnel_result.port)) as rsd:
                        async with DvtSecureSocketProxyService(rsd) as dvt:
                            simulation = LocationSimulation(dvt)
                            await simulation.clear()
                            if mode == "set":
                                await simulation.set(latitude, longitude)
                                mark_ready(status_path)
                                await hold_simulation(simulation)
                            else:
                                await simulation.clear()
            finally:
                await tunnel_proxy.close()
                await lockdown.close()


        async def main():
            mode = sys.argv[1]
            udid = sys.argv[2]
            version = sys.argv[3]
            status_path = sys.argv[4]
            latitude = float(sys.argv[5]) if mode == "set" else None
            longitude = float(sys.argv[6]) if mode == "set" else None

            parsed_version = parse_version(version)

            if parsed_version[0] < 17:
                await run_pre_ios17(mode, udid, status_path, latitude, longitude)
            elif parsed_version < (17, 4):
                await run_ios17_quic(mode, udid, status_path, latitude, longitude)
            else:
                await run_ios17_tcp(mode, udid, status_path, latitude, longitude)


        try:
            asyncio.run(main())
        except ModuleNotFoundError as error:
            if error.name and error.name.startswith("pymobiledevice3"):
                install_command = f"{shlex.quote(sys.executable)} -m pip install pymobiledevice3"
                print("pymobiledevice3 is not installed for the resolved Python executable.", file=sys.stderr)
                print(f"Resolved Python: {sys.executable}", file=sys.stderr)
                print(f"Install command: {install_command}", file=sys.stderr)
            else:
                print(f"Missing Python module: {error.name}", file=sys.stderr)
            raise SystemExit(2)
        except Exception as error:
            print(str(error), file=sys.stderr)
            raise SystemExit(1)
        """#

    static func makeHelperFiles() throws -> (statusURL: URL, askpassScriptURL: URL) {
        let helperDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "teleport-helper",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)

        let statusURL = helperDirectory.appendingPathComponent(UUID().uuidString + ".status")
        let askpassScriptURL = helperDirectory.appendingPathComponent(UUID().uuidString + "-askpass.sh")
        try createAskpassScript(at: askpassScriptURL)

        return (statusURL, askpassScriptURL)
    }

    static func helperArguments(
        mode: String,
        device: Device,
        coordinate: LocationCoordinate?,
        statusURL: URL
    ) -> [String] {
        var arguments = ["-c", pythonHelperScript, mode, device.id, device.osVersion, statusURL.path]

        if let coordinate {
            arguments.append(String(coordinate.latitude))
            arguments.append(String(coordinate.longitude))
        }

        return arguments
    }

    private static func createAskpassScript(at url: URL) throws {
        let script = """
            #!/bin/sh
            export TELEPORT_PROMPT=\(shellSingleQuoted(String(localized: TeleportStrings.usbAuthorizePrompt)))
            export TELEPORT_CANCEL=\(shellSingleQuoted(String(localized: TeleportStrings.cancel)))
            export TELEPORT_AUTHORIZE=\(shellSingleQuoted(String(localized: TeleportStrings.authorize)))
            export TELEPORT_PASSWORD_TITLE=\(shellSingleQuoted(String(localized: TeleportStrings.administratorPassword)))
            password=$(
                /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null
                    set dialogIcon to POSIX file "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/LockedIcon.icns" as alias
                    set promptText to system attribute "TELEPORT_PROMPT"
                    set cancelText to system attribute "TELEPORT_CANCEL"
                    set authorizeText to system attribute "TELEPORT_AUTHORIZE"
                    set titleText to system attribute "TELEPORT_PASSWORD_TITLE"
                    tell application "System Events" to activate
                    tell application "System Events" to display dialog promptText default answer "" with hidden answer buttons {cancelText, authorizeText} default button authorizeText with title titleText with icon dialogIcon
                    text returned of result
                APPLESCRIPT
            )
            status=$?

            if [ "$status" -ne 0 ]; then
                echo "__TELEPORT_AUTH_CANCELLED__" >&2
                exit 1
            fi

            printf '%s\n' "$password"
            """

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

struct XCDeviceRecord: Decodable {
    let simulator: Bool
    let operatingSystemVersion: String
    let available: Bool
    let platform: String
    let identifier: String
    let interface: String?
    let name: String
}

struct CoreDeviceListResponse: Decodable {
    let result: CoreDeviceResult
}

struct CoreDeviceResult: Decodable {
    let devices: [CoreDeviceRecord]
}

struct CoreDeviceRecord: Decodable {
    let connectionProperties: CoreDeviceConnectionProperties
    let deviceProperties: CoreDeviceProperties
    let hardwareProperties: CoreDeviceHardwareProperties
}

struct CoreDeviceConnectionProperties: Decodable {
    let pairingState: String
}

struct CoreDeviceProperties: Decodable {
    let developerModeStatus: String
}

struct CoreDeviceHardwareProperties: Decodable {
    let udid: String
}