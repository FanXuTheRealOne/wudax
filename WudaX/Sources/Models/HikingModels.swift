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

enum InjuryLocation: String, CaseIterable, Codable, Equatable, Sendable {
    case none = "没有当前伤病"
    case knee = "膝盖"
    case ankleFoot = "脚踝 / 足部"
    case hipBack = "髋部 / 腰背"
    case shoulderArm = "肩部 / 手臂"
    case multiple = "多个部位"
    case other = "其他部位"
}

enum SurgeryHistory: String, CaseIterable, Codable, Equatable, Sendable {
    case none = "没有做过手术"
    case recovered = "做过，已完全恢复"
    case recovering = "做过，仍在恢复或有限制"
    case unknown = "做过，但不确定是否适合运动"
}

enum SurgeryLocation: String, CaseIterable, Codable, Equatable, Sendable {
    case knee = "膝盖 / 下肢"
    case ankleFoot = "脚踝 / 足部"
    case hipBack = "髋部 / 腰背"
    case shoulderArm = "肩部 / 手臂"
    case abdomenChest = "胸部 / 腹部"
    case other = "其他部位"
}

enum MedicalConsideration: String, CaseIterable, Codable, Equatable, Sendable {
    case none = "没有需要特别注意的情况"
    case chronicCondition = "有慢性病"
    case medication = "需要携带个人药物"
    case medicalRestriction = "有医生运动限制"
}

struct PersonalHealthProfile: Codable, Equatable, Sendable {
    var injury: InjuryLocation?
    var surgery: SurgeryHistory?
    var surgeryLocation: SurgeryLocation?
    var medicalConsideration: MedicalConsideration?

    init(injury: InjuryLocation? = nil,
         surgery: SurgeryHistory? = nil,
         surgeryLocation: SurgeryLocation? = nil,
         medicalConsideration: MedicalConsideration? = nil) {
        self.injury = injury
        self.surgery = surgery
        self.surgeryLocation = surgeryLocation
        self.medicalConsideration = medicalConsideration
    }

    var isComplete: Bool {
        guard injury != nil, let surgery, medicalConsideration != nil else { return false }
        return surgery == .none || surgeryLocation != nil
    }

    var readinessPenalty: Int {
        let injuryPenalty: Int = injury.map { value in
            switch value {
            case .none: 0
            case .knee: 10
            case .multiple: 14
            case .ankleFoot, .hipBack, .shoulderArm, .other: 8
            }
        } ?? 0
        let surgeryPenalty: Int = surgery.map { value in
            switch value {
            case .none: 0
            case .recovered: 2
            case .recovering: 12
            case .unknown: 8
            }
        } ?? 0
        let medicalPenalty: Int = medicalConsideration.map { value in
            switch value {
            case .none: 0
            case .chronicCondition: 8
            case .medication: 4
            case .medicalRestriction: 12
            }
        } ?? 0
        return injuryPenalty + surgeryPenalty + medicalPenalty
    }

    var cautionReasons: [String] {
        var reasons: [String] = []
        if let injury {
            switch injury {
            case .none: break
            case .knee: reasons.append("当前或近期有膝部伤病")
            case .ankleFoot: reasons.append("当前或近期有脚踝/足部伤病")
            case .hipBack: reasons.append("当前或近期有髋部/腰背伤病")
            case .shoulderArm: reasons.append("当前或近期有肩部/手臂伤病")
            case .multiple: reasons.append("当前或近期有多个部位伤病")
            case .other: reasons.append("当前或近期有其他部位伤病")
            }
        }
        if let surgery {
            switch surgery {
            case .recovering: reasons.append("有手术史且仍在恢复或存在活动限制")
            case .unknown: reasons.append("有手术史但运动限制尚未确认")
            case .none, .recovered: break
            }
            if surgery != .none, let surgeryLocation {
                reasons.append("既往手术部位：\(surgeryLocation.rawValue)")
            }
        }
        if let medicalConsideration {
            switch medicalConsideration {
            case .chronicCondition: reasons.append("有慢性病史，需要按个人医疗建议活动")
            case .medication: reasons.append("需要携带个人药物")
            case .medicalRestriction: reasons.append("存在医生给出的运动限制")
            case .none: break
            }
        }
        return reasons
    }
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
