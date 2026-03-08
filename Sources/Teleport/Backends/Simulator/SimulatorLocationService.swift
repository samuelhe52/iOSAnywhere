import Foundation

actor SimulatorLocationService: LocationSimulationService {
    let kind: DeviceKind = .simulator

    private let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

    private var connectedDeviceID: String?
    private var lastCoordinate: LocationCoordinate?

    func discoverDevices() async throws -> [Device] {
        let output = try CommandRunner.run(
            xcrunURL,
            arguments: ["simctl", "list", "devices", "available", "--json"]
        )
        let response = try JSONDecoder().decode(SimctlDeviceList.self, from: output.stdout)

        return response.devices
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
    }

    func connect(to device: Device) async throws {
        do {
            _ = try CommandRunner.run(xcrunURL, arguments: ["simctl", "boot", device.id])
        } catch {
            let message = error.localizedDescription
            guard message.contains("current state: Booted") else {
                throw error
            }
        }

        _ = try CommandRunner.run(xcrunURL, arguments: ["simctl", "bootstatus", device.id, "-b"])
        connectedDeviceID = device.id
    }

    func disconnect() async {
        connectedDeviceID = nil
        lastCoordinate = nil
    }

    func setLocation(_ coordinate: LocationCoordinate) async throws {
        guard let connectedDeviceID else {
            throw ServiceError.invalidSelection
        }

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
    }

    func clearLocation() async throws {
        guard let connectedDeviceID else {
            throw ServiceError.invalidSelection
        }

        _ = try CommandRunner.run(
            xcrunURL,
            arguments: ["simctl", "location", connectedDeviceID, "clear"]
        )
        lastCoordinate = nil
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
