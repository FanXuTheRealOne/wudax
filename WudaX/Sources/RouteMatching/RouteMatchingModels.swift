import Foundation

struct RouteCoordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct PreparedRouteVertex: Codable, Equatable, Sendable {
    var coordinate: RouteCoordinate
    var localXMeters: Double
    var localYMeters: Double
    var elevationMeters: Double?
    var cumulativeDistanceMeters: Double
    var remainingDistanceMeters: Double
    var remainingAscentMeters: Double
    var sourcePointIndex: Int
}

struct PreparedRouteSegment: Codable, Equatable, Sendable {
    var index: Int
    var sourceSegmentIndex: Int
    var startVertexIndex: Int
    var endVertexIndex: Int
    var lengthMeters: Double
    var cumulativeStartMeters: Double
    var cumulativeEndMeters: Double
    var bearingDegrees: Double
    var gradePercent: Double?
    var ascentMeters: Double
    var remainingDistanceAtStartMeters: Double
    var remainingAscentAtStartMeters: Double
    var minimumX: Double
    var maximumX: Double
    var minimumY: Double
    var maximumY: Double
}

struct PreparedRouteWaypoint: Codable, Equatable, Sendable {
    var name: String?
    var coordinate: RouteCoordinate
    var elevationMeters: Double?
    var routeProgressMeters: Double
    var distanceFromRouteMeters: Double
}

struct RouteSegmentPair: Codable, Equatable, Hashable, Sendable {
    var firstSegmentIndex: Int
    var secondSegmentIndex: Int
}

struct RouteTopologyFlags: Codable, Equatable, Sendable {
    var isLoop: Bool
    var isOutAndBack: Bool
    var hasNearbyParallelSegments: Bool
}

struct PreparedGPXRoute: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var name: String
    var sourcePointCount: Int
    var sourceSegmentCount: Int
    var origin: RouteCoordinate
    var vertices: [PreparedRouteVertex]
    var segments: [PreparedRouteSegment]
    var waypoints: [PreparedRouteWaypoint]
    var turnVertexIndices: [Int]
    var ambiguousSegmentPairs: [RouteSegmentPair]
    var flags: RouteTopologyFlags
    var totalDistanceMeters: Double
    var totalAscentMeters: Double
}

enum RouteMatchConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
    case none
}

enum RouteLocationSource: String, Codable, Equatable, Sendable {
    case gpsMatched = "gps_matched"
    case estimated
    case lastKnown = "last_known"
}

enum OffRouteConfidence: String, Codable, Equatable, Sendable {
    case none
    case low
    case medium
    case high
}

struct RouteLocationInput: Equatable, Sendable {
    var coordinate: RouteCoordinate
    var horizontalAccuracyMeters: Double
    var timestamp: Date
    var speedMetersPerSecond: Double?
    var courseDegrees: Double?
    var altitudeMeters: Double?
    var cadenceStepsPerMinute: Double?
}

struct RouteMatchResult: Codable, Equatable, Sendable {
    var routeProgressMeters: Double
    var matchedCoordinate: RouteCoordinate
    var distanceToRouteMeters: Double
    var remainingDistanceMeters: Double
    var remainingAscentMeters: Double
    var nextWaypoint: PreparedRouteWaypoint?
    var distanceToNextWaypointMeters: Double?
    var confidence: RouteMatchConfidence
    var isOffRoute: Bool
    var offRouteConfidence: OffRouteConfidence
    var lastReliableProgressMeters: Double
    var locationSource: RouteLocationSource
    var progressRangeStartMeters: Double?
    var progressRangeEndMeters: Double?
    var reason: String
}
