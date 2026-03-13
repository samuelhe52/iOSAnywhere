import Foundation

enum USBDeviceScript {
    static let pythonResolutionCommand =
        #"python3 -c 'import os, sys; print(os.path.realpath(sys.executable))'"#

    static let pythonHelperScript = #"""
        import asyncio
        import os
        import re
        import shlex
        import sys


        def parse_version(version_text):
            parts = [int(part) for part in re.findall(r"\d+", version_text)[:2]]
            while len(parts) < 2:
                parts.append(0)
            return tuple(parts)


        def write_status(status_path, value):
            with open(status_path, "w", encoding="utf-8") as handle:
                handle.write(f"{value}\n")


        def mark_ready(status_path):
            write_status(status_path, "READY")


        async def session_command_loop(simulation, stop_path):
            loop = asyncio.get_running_loop()
            reader = asyncio.StreamReader()
            protocol = asyncio.StreamReaderProtocol(reader)
            transport, _ = await loop.connect_read_pipe(lambda: protocol, sys.stdin)

            try:
                while True:
                    if os.path.exists(stop_path):
                        break

                    try:
                        line = await asyncio.wait_for(reader.readline(), timeout=0.1)
                    except asyncio.TimeoutError:
                        continue

                    if not line:
                        break

                    command = line.decode("utf-8").strip()
                    if not command:
                        continue

                    parts = command.split()
                    action = parts[0].upper()

                    if action == "SET" and len(parts) == 3:
                        await simulation.set(float(parts[1]), float(parts[2]))
                    elif action == "CLEAR":
                        await simulation.clear()
                    elif action == "STOP":
                        break
                    else:
                        print(f"Unsupported helper command: {command}", file=sys.stderr)
            finally:
                transport.close()
                await simulation.clear()


        async def run_pre_ios17(mode, udid, connection_type, status_path, stop_path, latitude, longitude):
            from pymobiledevice3.lockdown import create_using_usbmux
            from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

            write_status(status_path, "LOCKDOWN")
            lockdown = await create_using_usbmux(udid, connection_type=connection_type, autopair=True)
            try:
                write_status(status_path, "DVT")
                async with DvtSecureSocketProxyService(lockdown) as dvt:
                    simulation = LocationSimulation(dvt)
                    await simulation.clear()
                    if mode == "set":
                        await simulation.set(latitude, longitude)
                        mark_ready(status_path)
                        await session_command_loop(simulation, stop_path)
                    else:
                        await simulation.clear()
            finally:
                await lockdown.close()


        async def run_ios17_quic(mode, udid, status_path, stop_path, latitude, longitude):
            from pymobiledevice3.bonjour import DEFAULT_BONJOUR_TIMEOUT
            from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
            from pymobiledevice3.remote.tunnel_service import get_remote_pairing_tunnel_services
            from pymobiledevice3.remote.utils import resume_remoted_if_required, stop_remoted_if_required
            from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

            stop_remoted_if_required()
            service_provider = None

            try:
                write_status(status_path, "DISCOVERING_TUNNEL")
                service_providers = await get_remote_pairing_tunnel_services(DEFAULT_BONJOUR_TIMEOUT, udid=udid)
                service_provider = service_providers[0] if service_providers else None
                if service_provider is None:
                    raise RuntimeError(
                        f"No remote pairing tunnel service found for {udid}. Connect the device over USB once to create a pairing record, unlock it, and keep it on the same local network before retrying Wi-Fi."
                    )

                write_status(status_path, "STARTING_TUNNEL")
                async with service_provider.start_quic_tunnel() as tunnel_result:
                    resume_remoted_if_required()
                    write_status(status_path, "RSD")
                    async with RemoteServiceDiscoveryService((tunnel_result.address, tunnel_result.port)) as rsd:
                        write_status(status_path, "DVT")
                        async with DvtSecureSocketProxyService(rsd) as dvt:
                            simulation = LocationSimulation(dvt)
                            await simulation.clear()
                            if mode == "set":
                                await simulation.set(latitude, longitude)
                                mark_ready(status_path)
                                await session_command_loop(simulation, stop_path)
                            else:
                                await simulation.clear()
            finally:
                if service_provider is not None:
                    await service_provider.close()
                resume_remoted_if_required()


        async def run_ios17_tcp(mode, udid, connection_type, status_path, stop_path, latitude, longitude):
            from pymobiledevice3.lockdown import create_using_usbmux
            from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
            from pymobiledevice3.remote.tunnel_service import CoreDeviceTunnelProxy
            from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

            write_status(status_path, "LOCKDOWN")
            lockdown = await create_using_usbmux(udid, connection_type=connection_type, autopair=True)
            write_status(status_path, "CREATING_TUNNEL_PROXY")
            tunnel_proxy = await CoreDeviceTunnelProxy.create(lockdown)
            try:
                write_status(status_path, "STARTING_TUNNEL")
                async with tunnel_proxy.start_tcp_tunnel() as tunnel_result:
                    write_status(status_path, "RSD")
                    async with RemoteServiceDiscoveryService((tunnel_result.address, tunnel_result.port)) as rsd:
                        write_status(status_path, "DVT")
                        async with DvtSecureSocketProxyService(rsd) as dvt:
                            simulation = LocationSimulation(dvt)
                            await simulation.clear()
                            if mode == "set":
                                await simulation.set(latitude, longitude)
                                mark_ready(status_path)
                                await session_command_loop(simulation, stop_path)
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
            stop_path = sys.argv[5]
            device_kind = sys.argv[6]
            latitude = float(sys.argv[7]) if mode == "set" else None
            longitude = float(sys.argv[8]) if mode == "set" else None

            parsed_version = parse_version(version)
            connection_type = "USB" if device_kind == "physicalUSB" else "Network"

            if parsed_version[0] < 17:
                await run_pre_ios17(mode, udid, connection_type, status_path, stop_path, latitude, longitude)
            elif device_kind == "physicalNetwork":
                await run_ios17_tcp(mode, udid, connection_type, status_path, stop_path, latitude, longitude)
            elif parsed_version < (17, 4):
                await run_ios17_quic(mode, udid, status_path, stop_path, latitude, longitude)
            else:
                await run_ios17_tcp(mode, udid, connection_type, status_path, stop_path, latitude, longitude)


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

    static func makeHelperFiles() throws -> (statusURL: URL, stopURL: URL, promptScriptURL: URL) {
        let helperDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "teleport-helper",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)

        let statusURL = helperDirectory.appendingPathComponent(UUID().uuidString + ".status")
        let stopURL = helperDirectory.appendingPathComponent(UUID().uuidString + ".stop")
        let promptScriptURL = helperDirectory.appendingPathComponent(UUID().uuidString + "-prompt.sh")
        try createAskpassScript(at: promptScriptURL)

        return (statusURL, stopURL, promptScriptURL)
    }

    static func helperArguments(
        mode: String,
        device: Device,
        coordinate: LocationCoordinate?,
        statusURL: URL,
        stopURL: URL
    ) -> [String] {
        var arguments = [
            "-u", "-c", pythonHelperScript, mode, device.id, device.osVersion, statusURL.path, stopURL.path,
            device.kind.rawValue
        ]

        if let coordinate {
            arguments.append(String(coordinate.latitude))
            arguments.append(String(coordinate.longitude))
        }

        return arguments
    }

    private static func createAskpassScript(at url: URL) throws {
        let promptText = shellSingleQuoted(String(localized: TeleportStrings.usbAuthorizePrompt))
        let cancelText = shellSingleQuoted(String(localized: TeleportStrings.cancel))
        let authorizeText = shellSingleQuoted(String(localized: TeleportStrings.authorize))
        let titleText = shellSingleQuoted(String(localized: TeleportStrings.administratorPassword))

        let scriptLines = [
            "#!/bin/sh",
            "password=$(",
            "/usr/bin/osascript - \(promptText) \(cancelText) \(authorizeText) \(titleText) <<'APPLESCRIPT' 2>/dev/null",
            "on run argv",
            "set dialogIcon to POSIX file \"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/LockedIcon.icns\" as alias",
            "set promptText to item 1 of argv",
            "set cancelText to item 2 of argv",
            "set authorizeText to item 3 of argv",
            "set titleText to item 4 of argv",
            "tell application \"System Events\" to activate",
            "tell application \"System Events\" to display dialog promptText default answer \"\" with hidden answer buttons {cancelText, authorizeText} default button authorizeText with title titleText with icon dialogIcon",
            "return text returned of result",
            "end run",
            "APPLESCRIPT",
            ")",
            "status=$?",
            "",
            "if [ \"$status\" -ne 0 ]; then",
            "    echo \"__TELEPORT_AUTH_CANCELLED__\" >&2",
            "    exit 1",
            "fi",
            "",
            "printf '%s\\n' \"$password\""
        ]
        let script = scriptLines.joined(separator: "\n") + "\n"

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}