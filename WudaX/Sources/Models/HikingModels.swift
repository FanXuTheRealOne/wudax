import Foundation

enum RoutePurpose: String, Codable, Equatable, Sendable {
    case plannedRoute
    case recordedActivity
}

struct GPXTrackPoint: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevationMeters: Double?
    var time: Date?
    var speedMetersPerSecond: Double?
}

struct GPXTrackSegment: Codable, Equatable, Sendable {
    var points: [GPXTrackPoint]
}

struct GPXWaypoint: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevationMeters: Double?
    var name: String?
}

struct GPXDocument: Codable, Equatable, Sendable {
    var name: String
    var creator: String?
    var segments: [GPXTrackSegment]
    var waypoints: [GPXWaypoint]
    var purpose: RoutePurpose

    var points: [GPXTrackPoint] { segments.flatMap(\.points) }

    func copyForPlanning() -> GPXDocument {
        var copy = self
        copy.purpose = .plannedRoute
        copy.segments = segments.map { segment in
            GPXTrackSegment(points: segment.points.map { point in
                var stripped = point
                stripped.time = nil
                stripped.speedMetersPerSecond = nil
                return stripped
            })
        }
        return copy
    }
}

struct TrackStatistics: Codable, Equatable, Sendable {
    var distanceMeters: Double
    var ascentMeters: Double
    var descentMeters: Double
    var minimumElevationMeters: Double?
    var maximumElevationMeters: Double?
    var recordedDuration: TimeInterval?
    var maximumTimeGap: TimeInterval
    var isLoop: Bool
}

struct DataQualityIssue: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case tooFewPoints
        case missingElevation
        case missingTime
        case timeRegression
        case longTimeGap
        case repeatedCoordinate
    }

    var id = UUID()
    var kind: Kind
    var count: Int
    var message: String
}

struct AnalyzedGPX: Codable, Equatable, Sendable {
    var document: GPXDocument
    var statistics: TrackStatistics
    var qualityIssues: [DataQualityIssue]

    var qualityScore: Int {
        let penalty = qualityIssues.reduce(0) { partial, issue in
            switch issue.kind {
            case .tooFewPoints: partial + 45
            case .timeRegression: partial + min(issue.count * 5, 20)
            case .longTimeGap: partial + min(issue.count * 8, 24)
            case .missingElevation, .missingTime: partial + min(issue.count, 20)
            case .repeatedCoordinate: partial + min(issue.count / 10, 15)
            }
        }
        return max(0, 100 - penalty)
    }
}

