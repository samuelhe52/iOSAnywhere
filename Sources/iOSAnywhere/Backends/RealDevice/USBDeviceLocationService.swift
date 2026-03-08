import Foundation

actor USBDeviceLocationService: LocationSimulationService {
    let kind: DeviceKind = .physicalUSB

    private let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    private let sudoURL = URL(fileURLWithPath: "/usr/bin/sudo")
    private let python3URL = URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3")

    private var connectedDevice: Device?
    private var activeCoordinate: LocationCoordinate?
    private var simulationHelper: SimulationHelper?

    func discoverDevices() async throws -> [Device] {
        let xcdeviceOutput = try CommandRunner.run(xcrunURL, arguments: ["xcdevice", "list"])
        let devices = try JSONDecoder().decode([XCDeviceRecord].self, from: xcdeviceOutput.stdout)
        let metadata = (try? loadCoreDeviceMetadata()) ?? [:]

        return devices
            .filter { !$0.simulator && $0.platform == "com.apple.platform.iphoneos" && $0.interface == "usb" }
            .map { device in
                let coreDevice = metadata[device.identifier]
                let developerMode = coreDevice?.deviceProperties.developerModeStatus ?? "unknown"
                let pairingState =
                    coreDevice?.connectionProperties.pairingState ?? (device.available ? "paired" : "unavailable")

                return Device(
                    id: device.identifier,
                    name: device.name,
                    kind: .physicalUSB,
                    osVersion: device.operatingSystemVersion,
                    isAvailable: device.available,
                    details: "USB · \(pairingState) · dev mode \(developerMode)"
                )
            }
            .sorted { $0.name < $1.name }
    }

    func connect(to device: Device) async throws {
        guard device.isAvailable else {
            throw ServiceError.unavailable("The selected device is not currently available over USB.")
        }

        if connectedDevice?.id != device.id {
            try? await stopSimulationHelper()
            activeCoordinate = nil
        }

        connectedDevice = device
    }

    func disconnect() async {
        try? await stopSimulationHelper()
        connectedDevice = nil
        activeCoordinate = nil
    }

    func setLocation(_ coordinate: LocationCoordinate) async throws {
        guard let connectedDevice else {
            throw ServiceError.invalidSelection
        }

        try? await stopSimulationHelper()

        let helper = try makeSimulationHelper(mode: "set", device: connectedDevice, coordinate: coordinate)

        do {
            try helper.process.run()
        } catch {
            helper.cleanup()
            throw ServiceError.unavailable("Failed to launch the physical-device helper: \(error.localizedDescription)")
        }

        do {
            try await waitForHelperReady(helper)
        } catch {
            if helper.process.isRunning {
                helper.process.terminate()
                helper.process.waitUntilExit()
            }
            helper.cleanup()
            throw error
        }

        simulationHelper = helper
        activeCoordinate = coordinate
    }

    func clearLocation() async throws {
        guard let connectedDevice else {
            throw ServiceError.invalidSelection
        }

        if simulationHelper != nil {
            try await stopSimulationHelper()
            activeCoordinate = nil
            return
        }

        try runOneShotHelper(mode: "clear", device: connectedDevice, coordinate: nil)
        activeCoordinate = nil
    }

    private func loadCoreDeviceMetadata() throws -> [String: CoreDeviceRecord] {
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("iosanywhere-devicectl.json")

        _ = try CommandRunner.run(
            xcrunURL,
            arguments: ["devicectl", "list", "devices", "--json-output", outputURL.path]
        )

        let data = try Data(contentsOf: outputURL)
        let response = try JSONDecoder().decode(CoreDeviceListResponse.self, from: data)
        return Dictionary(uniqueKeysWithValues: response.result.devices.map { ($0.hardwareProperties.udid, $0) })
    }

    private func makeSimulationHelper(
        mode: String,
        device: Device,
        coordinate: LocationCoordinate?
    ) throws -> SimulationHelper {
        let helperFiles = try makeHelperFiles()
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = sudoURL
        process.arguments = ["-A", python3URL.path] + helperArguments(
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
                "SUDO_PROMPT": "iOSAnywhere requires administrator privileges for physical-device location simulation."
            ],
            uniquingKeysWith: { _, new in new }
        )

        return SimulationHelper(
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe,
            stderr: stderrPipe,
            statusURL: helperFiles.statusURL,
            askpassScriptURL: helperFiles.askpassScriptURL
        )
    }

    private func runOneShotHelper(mode: String, device: Device, coordinate: LocationCoordinate?) throws {
        let helper = try makeSimulationHelper(mode: mode, device: device, coordinate: coordinate)

        do {
            try helper.process.run()
        } catch {
            helper.cleanup()
            throw ServiceError.unavailable("Failed to launch the physical-device helper: \(error.localizedDescription)")
        }

        helper.process.waitUntilExit()
        let stdout = helper.stdout.fileHandleForReading.readDataToEndOfFile()
        let stderr = helper.stderr.fileHandleForReading.readDataToEndOfFile()
        helper.cleanup()

        guard helper.process.terminationStatus == 0 else {
            throw helperFailure(
                stdout: stdout,
                stderr: stderr,
                fallback: "Failed to clear the physical-device simulated location."
            )
        }
    }

    private func makeHelperFiles() throws -> (statusURL: URL, askpassScriptURL: URL) {
        let helperDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "iosanywhere-helper",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)

        let statusURL = helperDirectory.appendingPathComponent(UUID().uuidString + ".status")
        let askpassScriptURL = helperDirectory.appendingPathComponent(UUID().uuidString + "-askpass.sh")
        try createAskpassScript(at: askpassScriptURL)

        return (statusURL, askpassScriptURL)
    }

    private func createAskpassScript(at url: URL) throws {
        let script = #"""
#!/bin/sh
/usr/bin/osascript \
  -e 'tell application "System Events" to activate' \
  -e 'tell application "System Events" to display dialog "iOSAnywhere needs your administrator password to simulate location on a physical device." default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK" with title "iOSAnywhere"' \
  -e 'text returned of result'
"""#

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func helperArguments(
        mode: String,
        device: Device,
        coordinate: LocationCoordinate?,
        statusURL: URL
    ) -> [String] {
        var arguments = ["-c", Self.pythonHelperScript, mode, device.id, device.osVersion, statusURL.path]

        if let coordinate {
            arguments.append(String(coordinate.latitude))
            arguments.append(String(coordinate.longitude))
        }

        return arguments
    }

    private func stopSimulationHelper() async throws {
        guard let simulationHelper else {
            return
        }

        self.simulationHelper = nil
        simulationHelper.stdin.closeFile()
        await waitForProcessExit(simulationHelper.process, timeoutNanoseconds: 5_000_000_000)

        if simulationHelper.process.isRunning {
            simulationHelper.process.terminate()
            simulationHelper.process.waitUntilExit()
        }

        let stdout = simulationHelper.stdout.fileHandleForReading.readDataToEndOfFile()
        let stderr = simulationHelper.stderr.fileHandleForReading.readDataToEndOfFile()
        simulationHelper.cleanup()

        guard simulationHelper.process.terminationStatus == 0 else {
            throw helperFailure(
                stdout: stdout,
                stderr: stderr,
                fallback: "Failed to clear the physical-device simulated location."
            )
        }
    }

    private func waitForHelperReady(_ helper: SimulationHelper) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 30_000_000_000

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if FileManager.default.fileExists(atPath: helper.statusURL.path) {
                let status = (try? String(contentsOf: helper.statusURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard status == "READY" else {
                    throw ServiceError.unavailable(status ?? "The physical-device helper reported an invalid startup state.")
                }
                return
            }

            if !helper.process.isRunning {
                throw helperFailure(
                    stdout: helper.stdout.fileHandleForReading.readDataToEndOfFile(),
                    stderr: helper.stderr.fileHandleForReading.readDataToEndOfFile(),
                    fallback: "Physical-device location simulation exited before reporting ready."
                )
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw ServiceError.unavailable(
            "Timed out waiting for administrator approval or helper startup while enabling physical-device location simulation.")
    }

    private func waitForProcessExit(_ process: Process, timeoutNanoseconds: UInt64) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while process.isRunning && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func helperFailure(stdout: Data, stderr: Data, fallback: String) -> ServiceError {
        let output = [
            String(decoding: stderr, as: UTF8.self),
            String(decoding: stdout, as: UTF8.self)
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })

        return ServiceError.unavailable(output ?? fallback)
    }

    private struct SimulationHelper {
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

    private static let pythonHelperScript = #"""
import asyncio
import re
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
        print("pymobiledevice3 is not installed. Install it with: python3 -m pip install pymobiledevice3", file=sys.stderr)
    else:
        print(f"Missing Python module: {error.name}", file=sys.stderr)
    raise SystemExit(2)
except Exception as error:
    print(str(error), file=sys.stderr)
    raise SystemExit(1)
"""#
}

fileprivate struct XCDeviceRecord: Decodable {
    let simulator: Bool
    let operatingSystemVersion: String
    let available: Bool
    let platform: String
    let identifier: String
    let interface: String?
    let name: String
}

fileprivate struct CoreDeviceListResponse: Decodable {
    let result: CoreDeviceResult
}

fileprivate struct CoreDeviceResult: Decodable {
    let devices: [CoreDeviceRecord]
}

fileprivate struct CoreDeviceRecord: Decodable {
    let connectionProperties: CoreDeviceConnectionProperties
    let deviceProperties: CoreDeviceProperties
    let hardwareProperties: CoreDeviceHardwareProperties
}

fileprivate struct CoreDeviceConnectionProperties: Decodable {
    let pairingState: String
}

fileprivate struct CoreDeviceProperties: Decodable {
    let developerModeStatus: String
}

fileprivate struct CoreDeviceHardwareProperties: Decodable {
    let udid: String
}
