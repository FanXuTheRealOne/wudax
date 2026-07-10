import Foundation

// MARK: - 路线

struct Route: Identifiable {
    let id = UUID()
    var name: String
    var distanceKm: Double
    var ascentM: Double
    var descentM: Double
    var estimatedHours: Double
    var elevationProfile: [Double]     // 采样海拔序列
    var riskPoints: [RiskPoint]
    var hasUnverifiedSegment: Bool     // 无路 / 探路段
    var isOutAndBack: Bool             // 原路返回
    var waterSourceCount: Int

    struct RiskPoint: Identifiable {
        let id = UUID()
        var profileIndex: Int          // 在剖面图中的位置
        var title: String
        var detail: String
    }
}

// MARK: - 行程计划（预算卡）

struct TripPlan {
    var route: Route
    var departureTime: Date?
    var waterL: Double?
    var foodKcal: Double?
    var riskLevel: RiskLevel = .mediumHigh
    var topRisks: [String] = []
    var suggestedWaterL: Double = 3.0
    var suggestedFoodKcal: Double = 1600
    var checkpoints: [String] = []
    var sunsetTime: Date?

    var missingQuestions: [PlanQuestion] {
        var qs: [PlanQuestion] = []
        if departureTime == nil { qs.append(.departure) }
        if waterL == nil { qs.append(.water) }
        if foodKcal == nil { qs.append(.food) }
        return qs
    }
}

enum PlanQuestion: String, CaseIterable, Identifiable {
    case departure = "你几点出发？"
    case water = "身上实际带多少水？"
    case food = "身上实际带多少食物？"
    var id: String { rawValue }

    var options: [String] {
        switch self {
        case .departure: return ["05:30", "06:00", "06:30", "07:00"]
        case .water: return ["1.5 L", "2.0 L", "2.5 L", "3.0 L"]
        case .food: return ["800 kcal", "1200 kcal", "1600 kcal", "2000 kcal"]
        }
    }
}

// MARK: - 行中状态

struct TripStatus {
    var elapsedKm: Double = 0
    var elapsedHours: Double = 0
    var planDeltaMin: Int = 0          // 与计划的偏差（分钟，负为落后）
    var remainingWaterL: Double = 2.5
    var kneePain: Double = 0           // 0-10
    var drowsiness: Double = 0         // 0-10
    var hoursToSunset: Double = 8
    var upcomingLongDescent: Bool = false
    var profileIndex: Int = 0          // 当前在剖面图中的位置
}

// MARK: - 行中问询触发

enum CheckinTrigger: String {
    case timer = "定时状态确认"
    case beforeDescent = "长下坡前确认"
    case sunset = "日落风险重算"
    case slowProgress = "进度落后确认"
    case keypoint = "关键点确认"

    var explanation: String {
        switch self {
        case .timer: return "距上次确认已超过 90 分钟"
        case .beforeDescent: return "前方 800m 进入连续长下坡"
        case .sunset: return "距日落不足 3 小时"
        case .slowProgress: return "实际速度低于计划 18%"
        case .keypoint: return "已到达预设关键复核点"
        }
    }
}

// MARK: - 决策

struct AgentDecision {
    var verdict: AgentVerdict
    var reasons: [String]
    var watchHint: String              // 手表短提示
    var detail: String                 // 手机长解释
}

// MARK: - 疲劳档案

struct FatigueProfile {
    var descentToleranceKm: Double = 8.5    // 膝痛出现前的累计下降耐受
    var waterRatePerHour: Double = 0.35     // L/h
    var drowsinessAfterHours: Double = 7.0
    var tripsRecorded: Int = 3
}

// MARK: - 行后复盘

struct ReviewEntry: Identifiable {
    let id = UUID()
    var question: String
    var options: [String]
    var answer: String?
}
