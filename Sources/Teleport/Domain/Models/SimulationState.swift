import Foundation

enum DiscoveryState: Equatable, Sendable {
    case idle
    case discovering
    case ready
    case failed(UserFacingText)
}

enum DeviceConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(UserFacingText)
}

enum SimulationRunState: Equatable, Sendable {
    case idle
    case authorizing
    case simulating(LocationCoordinate)
    case stopping
    case failed(UserFacingText)
}
