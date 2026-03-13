import Foundation

enum RouteSource: String, CaseIterable, Codable, Sendable {
    case gpx
    case drawn
    case navigation
}

enum RoutePlaybackTimingMode: String, CaseIterable, Codable, Sendable {
    case recorded
    case fixedInterval
    case fixedSpeed
}

struct RouteWaypoint: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var coordinate: LocationCoordinate
    var timestamp: Date?
    var expectedTravelTime: TimeInterval?

    init(
        id: UUID = UUID(),
        coordinate: LocationCoordinate,
        timestamp: Date? = nil,
        expectedTravelTime: TimeInterval? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.expectedTravelTime = expectedTravelTime
    }
}

struct SimulatedRoute: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var source: RouteSource
    var waypoints: [RouteWaypoint]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        source: RouteSource,
        waypoints: [RouteWaypoint],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.waypoints = waypoints
        self.createdAt = createdAt
    }

    var startCoordinate: LocationCoordinate? {
        waypoints.first?.coordinate
    }

    var endCoordinate: LocationCoordinate? {
        waypoints.last?.coordinate
    }

    var pointCount: Int {
        waypoints.count
    }

    var totalDistanceMeters: Double {
        guard waypoints.count > 1 else {
            return 0
        }

        return zip(waypoints, waypoints.dropFirst()).reduce(0) { total, pair in
            total + pair.0.coordinate.distance(to: pair.1.coordinate)
        }
    }

    var recordedDurationSeconds: TimeInterval? {
        guard waypoints.count > 1 else {
            return nil
        }

        var totalDuration: TimeInterval = 0
        var hasTimingData = false

        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            if let startTimestamp = start.timestamp,
                let endTimestamp = end.timestamp
            {
                let timestampDelta = endTimestamp.timeIntervalSince(startTimestamp)
                if timestampDelta > 0 {
                    totalDuration += timestampDelta
                    hasTimingData = true
                    continue
                }
            }

            if let expectedTravelTime = end.expectedTravelTime,
                expectedTravelTime > 0
            {
                totalDuration += expectedTravelTime
                hasTimingData = true
            }
        }

        return hasTimingData ? totalDuration : nil
    }
}

struct RoutePlaybackProgress: Equatable, Sendable {
    var routeID: UUID
    var waypointIndex: Int
    var waypointCount: Int
    var currentCoordinate: LocationCoordinate?
    var traveledDistanceMeters: Double
    var totalDistanceMeters: Double

    var fractionCompleted: Double {
        if totalDistanceMeters > 0 {
            return min(max(traveledDistanceMeters / totalDistanceMeters, 0), 1)
        }

        guard waypointCount > 1 else {
            return waypointCount == 1 ? 1 : 0
        }

        let normalizedIndex = min(max(waypointIndex, 0), waypointCount - 1)
        return Double(normalizedIndex) / Double(waypointCount - 1)
    }

    var remainingWaypointCount: Int {
        max(0, waypointCount - waypointIndex - 1)
    }
}

enum RoutePlaybackState: Equatable, Sendable {
    case idle
    case ready
    case playing(RoutePlaybackProgress)
    case paused(RoutePlaybackProgress)
    case completed(RoutePlaybackProgress)
    case failed(UserFacingText)
}

extension LocationCoordinate {
    func distance(to other: LocationCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let latitude1 = latitude * .pi / 180.0
        let latitude2 = other.latitude * .pi / 180.0
        let latitudeDelta = (other.latitude - latitude) * .pi / 180.0
        let longitudeDelta = (other.longitude - longitude) * .pi / 180.0

        let haversine =
            sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let arc = 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))

        return earthRadiusMeters * arc
    }
}
