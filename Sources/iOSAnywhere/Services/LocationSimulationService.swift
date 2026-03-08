import Foundation

protocol LocationSimulationService: Sendable {
    var kind: DeviceKind { get }
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
            return "Select a device first."
        }
    }
}
