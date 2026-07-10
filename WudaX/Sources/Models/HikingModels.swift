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

enum DataFreshness: String, Codable, Equatable, Sendable {
    case current
    case recent
    case stale
    case unavailable
}

struct HealthReading: Codable, Equatable, Sendable {
    var value: Double
    var unit: String
    var sampledAt: Date
    var sourceName: String?
    var freshness: DataFreshness
}

enum HealthMetric: String, CaseIterable, Codable, Sendable {
    case age, sex, height, weight, bmi, bodyFat, leanBodyMass
    case workouts, routes, steps, walkingRunningDistance, flightsClimbed
    case activeEnergy, exerciseTime
    case heartRate, restingHeartRate, walkingHeartRateAverage
    case heartRateVariability, oxygenSaturation, respiratoryRate, vo2Max
    case sleepDuration, walkingAsymmetry, walkingDoubleSupport, walkingSpeed
    case sixMinuteWalkDistance
}

struct HealthSnapshot: Codable, Equatable, Sendable {
    var capturedAt: Date
    var readings: [HealthMetric: HealthReading]
    var unavailableMetrics: Set<HealthMetric>
    var authorizationGranted: Bool

    func reading(_ metric: HealthMetric) -> HealthReading? { readings[metric] }
}

struct ReadinessResult: Codable, Equatable, Sendable {
    var score: Int
    var label: String
    var reasons: [String]
    var missingInputs: [String]
}

struct RouteLoadResult: Codable, Equatable, Sendable {
    var score: Int
    var label: String
    var reasons: [String]
    var distanceKm: Double
    var ascentMeters: Double
    var descentMeters: Double
    var estimatedHours: Double
}

struct ChallengeGapResult: Codable, Equatable, Sendable {
    var score: Int
    var label: String
    var reasons: [String]
    var distanceGapKm: Double
    var ascentGapMeters: Double
    var descentGapKm: Double
}

struct SupplyBudgetResult: Codable, Equatable, Sendable {
    var waterLiters: Double
    var foodKilocalories: Double
    var waterRatePerHour: Double
    var feedingRatePerHour: Double
    var explanation: String
}

struct EquipmentItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var reason: String
    var required: Bool
}

struct RiskEvaluation: Codable, Equatable, Sendable {
    var level: RiskLevel
    var reasons: [String]
    var confidence: Double
    var staleData: Bool
}

enum ControlledAction: String, Codable, CaseIterable, Sendable {
    case continueRoute = "按计划继续"
    case rest = "原地休息 10 分钟"
    case hydrate = "补水并补充电解质"
    case slowDown = "降低速度"
    case shortenRoute = "缩短路线"
    case turnBack = "从当前节点折返"
    case checkSafety = "检查安全并联系同伴"
}

struct ActionRecommendation: Codable, Equatable, Sendable {
    var action: ControlledAction
    var title: String
    var detail: String
    var urgency: RiskLevel
}

struct RouteProgress: Codable, Equatable, Sendable {
    var nearestPointIndex: Int
    var distanceAlongRouteMeters: Double
    var distanceToRouteMeters: Double
    var fractionComplete: Double
    var estimatedElevationMeters: Double?
}

struct TripSummary: Codable, Equatable, Sendable {
    var plannedDistanceKm: Double
    var actualDistanceKm: Double
    var plannedHours: Double
    var actualHours: Double
    var planDeltaMinutes: Int
    var peakRisk: RiskLevel
    var keyEvents: [String]
}

struct TrainingAdvice: Codable, Equatable, Sendable {
    var headline: String
    var sessions: [String]
    var nextRouteAdjustment: String
}

enum OfflineMapMode: String, Codable, Equatable, Sendable {
    case fullOfflineMap = "完整离线地图"
    case routeOnly = "仅路线离线模式"
    case unavailable = "未准备"
}

struct OfflineResourceStatus: Codable, Equatable, Sendable {
    var mode: OfflineMapMode
    var progress: Double
    var estimatedSizeMB: Double
    var updatedAt: Date?
    var integrityMessage: String
    var isReady: Bool
}

struct TripEvent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var title: String
    var detail: String
    var risk: RiskLevel

    init(id: UUID = UUID(), date: Date, title: String, detail: String, risk: RiskLevel) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
        self.risk = risk
    }
}

struct RecordedTrackPoint: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevationMeters: Double?
    var timestamp: Date
    var horizontalAccuracyMeters: Double
}
