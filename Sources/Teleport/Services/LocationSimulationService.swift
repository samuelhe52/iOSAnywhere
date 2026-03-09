import Foundation
import OSLog

enum TeleportLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Teleport"

    static let search = Logger(subsystem: subsystem, category: "search")
    static let devices = Logger(subsystem: subsystem, category: "devices")
    static let simulation = Logger(subsystem: subsystem, category: "simulation")
    static let commands = Logger(subsystem: subsystem, category: "commands")
}

protocol LocationSimulationService: Sendable {
    var supportedKinds: [DeviceKind] { get }
    func discoverDevices() async throws -> [Device]
    func connect(to device: Device) async throws
    func disconnect() async
    func setLocation(_ coordinate: LocationCoordinate) async throws
    func clearLocation() async throws
}

enum ServiceError: LocalizedError, Equatable {
    case unsupported(String)
    case unavailable(String)
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .unsupported(let message), .unavailable(let message):
            return message
        case .invalidSelection:
            return String(localized: TeleportStrings.selectDeviceFirst)
        }
    }
}
