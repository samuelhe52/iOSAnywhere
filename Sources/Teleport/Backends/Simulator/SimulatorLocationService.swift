import Foundation
import OSLog

actor SimulatorLocationService: LocationSimulationService {
    let kind: DeviceKind = .simulator

    private let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

    private var connectedDeviceID: String?
    private var lastCoordinate: LocationCoordinate?

    func discoverDevices() async throws -> [Device] {
        TeleportLog.devices.info("Discovering available simulator devices")
        let output = try CommandRunner.run(
            xcrunURL,
            arguments: ["simctl", "list", "devices", "available", "--json"]
        )
        let response = try JSONDecoder().decode(SimctlDeviceList.self, from: output.stdout)

        let discoveredDevices = response.devices
            .flatMap { runtime, devices in
                devices.map {
                    Device(
                        id: $0.udid,
                        name: $0.name,
                        kind: .simulator,
                        osVersion: runtime.prettyRuntime,
                        isAvailable: $0.isAvailable,
                        details: "\($0.state)"
                    )
                }
            }
            .sorted {
                if $0.details == $1.details {
                    return $0.name < $1.name
                }
                return $0.details == "Booted"
            }

        TeleportLog.devices.info("Discovered \(discoveredDevices.count) simulator device(s)")
        return discoveredDevices
    }

    func connect(to device: Device) async throws {
        TeleportLog.devices.info("Booting simulator device \(device.logLabel, privacy: .public)")
        do {
            _ = try CommandRunner.run(xcrunURL, arguments: ["simctl", "boot", device.id])
        } catch {
            let message = error.localizedDescription
            guard message.contains("current state: Booted") else {
                TeleportLog.devices.error(
                    "Failed to boot simulator \(device.logLabel, privacy: .public): \(message, privacy: .public)"
                )
                throw error
            }

            TeleportLog.devices.debug("Simulator \(device.logLabel, privacy: .public) was already booted")
        }

        _ = try CommandRunner.run(xcrunURL, arguments: ["simctl", "bootstatus", device.id, "-b"])
        connectedDeviceID = device.id
        TeleportLog.devices.info("Simulator ready for connection: \(device.logLabel, privacy: .public)")
    }

    func disconnect() async {
        if connectedDeviceID != nil {
            TeleportLog.devices.info("Disconnecting simulator service from current device")
        }
        connectedDeviceID = nil
        lastCoordinate = nil
    }

    func setLocation(_ coordinate: LocationCoordinate) async throws {
        guard let connectedDeviceID else {
            throw ServiceError.invalidSelection
        }

        TeleportLog.simulation.info(
            "Setting simulator location for device id \(connectedDeviceID, privacy: .private) to \(coordinate.formatted, privacy: .private)"
        )
        _ = try CommandRunner.run(
            xcrunURL,
            arguments: [
                "simctl",
                "location",
                connectedDeviceID,
                "set",
                "\(coordinate.latitude),\(coordinate.longitude)"
            ]
        )
        lastCoordinate = coordinate
        TeleportLog.simulation.info("Simulator location set successfully")
    }

    func clearLocation() async throws {
        guard let connectedDeviceID else {
            throw ServiceError.invalidSelection
        }

        TeleportLog.simulation.info("Clearing simulator location for device id \(connectedDeviceID, privacy: .private)")
        _ = try CommandRunner.run(
            xcrunURL,
            arguments: ["simctl", "location", connectedDeviceID, "clear"]
        )
        lastCoordinate = nil
        TeleportLog.simulation.info("Simulator location cleared successfully")
    }
}

fileprivate struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDeviceRecord]]
}

fileprivate struct SimctlDeviceRecord: Decodable {
    let udid: String
    let isAvailable: Bool
    let state: String
    let name: String
}

extension String {
    fileprivate var prettyRuntime: String {
        guard let runtime = split(separator: ".").last else {
            return self
        }

        if runtime.hasPrefix("iOS-") {
            return "iOS " + runtime.dropFirst(4).replacing("-", with: ".")
        }

        return String(runtime).replacingOccurrences(of: "-", with: " ")
    }

    fileprivate func replacing(_ target: String, with replacement: String) -> String {
        replacingOccurrences(of: target, with: replacement)
    }
}
