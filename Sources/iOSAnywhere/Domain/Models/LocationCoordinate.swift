import Foundation

struct LocationCoordinate: Equatable, Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    static let applePark = LocationCoordinate(latitude: 37.3346, longitude: -122.0090)

    var formatted: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}
