import Foundation

enum DiscoveryState: Equatable, Sendable {
    case idle
    case discovering
    case ready
    case failed(String)
}

enum DeviceConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(String)
}

enum SimulationRunState: Equatable, Sendable {
    case idle
    case simulating(LocationCoordinate)
    case stopping
    case failed(String)
}
