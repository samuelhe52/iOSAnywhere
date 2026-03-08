import Foundation

enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case simulator
    case physicalUSB
}

struct Device: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var kind: DeviceKind
    var osVersion: String
    var isAvailable: Bool
    var details: String

    var logLabel: String {
        "\(name) [\(kind.rawValue)]"
    }
}
