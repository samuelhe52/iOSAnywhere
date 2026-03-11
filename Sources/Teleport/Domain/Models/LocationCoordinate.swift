import Foundation

struct LocationCoordinate: Equatable, Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    private static let metersPerLatitudeDegree = 111_320.0

    static let applePark = LocationCoordinate(latitude: 37.3346, longitude: -122.0090)

    func isApproximatelyEqual(to other: LocationCoordinate, tolerance: Double = 0.00001) -> Bool {
        abs(latitude - other.latitude) <= tolerance
            && abs(longitude - other.longitude) <= tolerance
    }

    var formatted: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    func offsetBy(northMeters: Double, eastMeters: Double) -> LocationCoordinate {
        let latitudeDelta = northMeters / Self.metersPerLatitudeDegree
        let longitudeScale = max(cos(latitude * .pi / 180.0), 0.01)
        let longitudeDelta = eastMeters / (Self.metersPerLatitudeDegree * longitudeScale)

        return LocationCoordinate(
            latitude: max(-90.0, min(90.0, latitude + latitudeDelta)),
            longitude: normalizedLongitude(longitude + longitudeDelta)
        )
    }

    private func normalizedLongitude(_ value: Double) -> Double {
        guard value < -180.0 || value > 180.0 else {
            return value
        }

        var longitude = value

        while longitude < -180.0 {
            longitude += 360.0
        }

        while longitude > 180.0 {
            longitude -= 360.0
        }

        return longitude
    }
}

enum ChinaCoordinateTransform {
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323
    private static let pi = Double.pi

    static func displayCoordinate(for simulationCoordinate: LocationCoordinate) -> LocationCoordinate {
        guard appliesToChinaRegion(simulationCoordinate) else {
            return simulationCoordinate
        }

        return wgs84ToGCJ02(simulationCoordinate)
    }

    static func simulationCoordinate(fromDisplayed displayedCoordinate: LocationCoordinate) -> LocationCoordinate {
        guard appliesToChinaRegion(displayedCoordinate) else {
            return displayedCoordinate
        }

        return gcj02ToWGS84(displayedCoordinate)
    }

    private static func appliesToChinaRegion(_ coordinate: LocationCoordinate) -> Bool {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude

        guard (18.0...54.5).contains(latitude), (73.5...135.1).contains(longitude) else {
            return false
        }

        return true
    }

    private static func wgs84ToGCJ02(_ coordinate: LocationCoordinate) -> LocationCoordinate {
        let delta = delta(for: coordinate)
        return LocationCoordinate(
            latitude: coordinate.latitude + delta.latitude,
            longitude: coordinate.longitude + delta.longitude
        )
    }

    private static func gcj02ToWGS84(_ coordinate: LocationCoordinate) -> LocationCoordinate {
        let transformed = wgs84ToGCJ02(coordinate)
        return LocationCoordinate(
            latitude: coordinate.latitude * 2 - transformed.latitude,
            longitude: coordinate.longitude * 2 - transformed.longitude
        )
    }

    private static func delta(for coordinate: LocationCoordinate) -> LocationCoordinate {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude

        var latitudeDelta = transformLatitude(longitude - 105.0, latitude - 35.0)
        var longitudeDelta = transformLongitude(longitude - 105.0, latitude - 35.0)
        let radLatitude = latitude / 180.0 * pi
        var magic = sin(radLatitude)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        latitudeDelta = (latitudeDelta * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi)
        longitudeDelta = (longitudeDelta * 180.0) / (a / sqrtMagic * cos(radLatitude) * pi)

        return LocationCoordinate(latitude: latitudeDelta, longitude: longitudeDelta)
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var value = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y
        value += 0.1 * x * y + 0.2 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        value += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        value += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return value
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var value = 300.0 + x + 2.0 * y + 0.1 * x * x
        value += 0.1 * x * y + 0.1 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        value += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        value += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0
        return value
    }
}
