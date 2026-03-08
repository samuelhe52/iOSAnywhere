import Foundation

actor USBDeviceLocationService: LocationSimulationService {
    let kind: DeviceKind = .physicalUSB

    private let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

    private var connectedDeviceID: String?
    private var activeCoordinate: LocationCoordinate?

    func discoverDevices() async throws -> [Device] {
        let xcdeviceOutput = try CommandRunner.run(xcrunURL, arguments: ["xcdevice", "list"])
        let devices = try JSONDecoder().decode([XCDeviceRecord].self, from: xcdeviceOutput.stdout)
        let metadata = (try? loadCoreDeviceMetadata()) ?? [:]

        return
            devices
            .filter {
                !$0.simulator && $0.platform == "com.apple.platform.iphoneos" && $0.interface == "usb"
            }
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
        connectedDeviceID = device.id
    }

    func disconnect() async {
        connectedDeviceID = nil
        activeCoordinate = nil
    }

    func setLocation(_ coordinate: LocationCoordinate) async throws {
        guard connectedDeviceID != nil else {
            throw ServiceError.invalidSelection
        }
        throw ServiceError.unavailable(
            "USB device discovery is live, but physical-device location simulation still needs the dedicated helper backend. GeoPort and LocationSimulator remain the implementation references for that next step."
        )
    }

    func clearLocation() async throws {
        guard connectedDeviceID != nil else {
            throw ServiceError.invalidSelection
        }
        activeCoordinate = nil
        throw ServiceError.unavailable(
            "USB device discovery is live, but clearing a physical-device simulated location still needs the dedicated helper backend."
        )
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
