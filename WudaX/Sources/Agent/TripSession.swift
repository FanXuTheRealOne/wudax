import Foundation
import SwiftUI
import Combine

// MARK: - 行程会话：贯穿五阶段的状态机

@MainActor
final class TripSession: ObservableObject {

    enum Phase {
        case home
        case planningChat      // 阶段一：行前追问
        case budgetCard        // 阶段一：预算卡
        case gate              // 阶段二：出发守门
        case inTrip            // 阶段三：行中
        case review            // 阶段五：行后复盘
    }

    @Published var phase: Phase = .home
    @Published var plan = SampleData.plan
    @Published var status = TripStatus()
    @Published var profile = FatigueProfile()

    // 行中
    @Published var activeCheckin: CheckinTrigger?
    @Published var lastDecision: AgentDecision?
    @Published var showRetreatSheet = false
    @Published var tripEndedByRetreat = false

    // 复盘
    @Published var reviewEntries = SampleData.reviewQuestions

    private var timer: AnyCancellable?

    init() {
        // 调试：WUDAX_PHASE 环境变量直接跳转到指定阶段（用于截图验证）
        if let target = ProcessInfo.processInfo.environment["WUDAX_PHASE"] {
            applyDebugPhase(target)
        }
    }

    private func applyDebugPhase(_ target: String) {
        plan.departureTime = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())
        plan.waterL = 2.5
        plan.foodKcal = 1200
        switch target {
        case "budget": phase = .budgetCard
        case "gate": phase = .gate
        case "trip":
            status.elapsedKm = 11.2
            status.elapsedHours = 4.5
            status.planDeltaMin = -18
            status.remainingWaterL = 1.2
            status.profileIndex = 18
            phase = .inTrip
        case "checkin":
            status.elapsedKm = 14.8
            status.profileIndex = 23
            status.upcomingLongDescent = true
            phase = .inTrip
            activeCheckin = .beforeDescent
        case "retreat":
            status.elapsedKm = 16.5
            status.elapsedHours = 6.8
            status.remainingWaterL = 0.5
            status.kneePain = 5
            status.drowsiness = 4
            status.hoursToSunset = 2.2
            status.profileIndex = 24
            status.upcomingLongDescent = true
            status.planDeltaMin = -42
            phase = .inTrip
            lastDecision = AgentEngine.evaluate(status: status, plan: plan)
            showRetreatSheet = true
        case "review": phase = .review
        default: break
        }
    }

    // MARK: 阶段流转

    func startPlanning() {
        plan = SampleData.plan
        phase = .planningChat
    }

    func answer(_ q: PlanQuestion, with option: String) {
        switch q {
        case .departure:
            let comps = option.split(separator: ":").compactMap { Int($0) }
            if comps.count == 2 {
                plan.departureTime = Calendar.current.date(
                    bySettingHour: comps[0], minute: comps[1], second: 0, of: Date())
            }
        case .water:
            plan.waterL = Double(option.replacingOccurrences(of: " L", with: ""))
        case .food:
            plan.foodKcal = Double(option.replacingOccurrences(of: " kcal", with: ""))
        }
        if plan.missingQuestions.isEmpty {
            withAnimation(.easeInOut(duration: 0.6)) { phase = .budgetCard }
        }
    }

    func confirmBudget() { withAnimation { phase = .gate } }

    func depart() {
        status = TripStatus()
        status.remainingWaterL = plan.waterL ?? 2.5
        status.hoursToSunset = hoursUntilSunset()
        withAnimation { phase = .inTrip }
        startSimulation()
    }

    func endTrip(retreated: Bool) {
        stopSimulation()
        tripEndedByRetreat = retreated
        activeCheckin = nil
        showRetreatSheet = false
        withAnimation { phase = .review }
    }

    func finishReview() {
        // 更新疲劳档案（MVP：简单启发式）
        if let kneeAnswer = reviewEntries.first(where: { $0.question.contains("膝痛") })?.answer,
           kneeAnswer != "没有膝痛" {
            profile.descentToleranceKm = max(profile.descentToleranceKm - 0.5, 3)
        }
        profile.tripsRecorded += 1
        reviewEntries = SampleData.reviewQuestions
        withAnimation { phase = .home }
    }

    // MARK: 行中模拟（MVP 演示：压缩时间推进行程）

    private func startSimulation() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func stopSimulation() { timer?.cancel(); timer = nil }

    private func tick() {
        guard phase == .inTrip, activeCheckin == nil, !showRetreatSheet else { return }
        // 1 秒 ≈ 12 分钟行程
        status.elapsedHours += 0.2
        status.elapsedKm = min(status.elapsedKm + 0.55, plan.route.distanceKm)
        status.hoursToSunset = max(status.hoursToSunset - 0.2, 0)
        status.remainingWaterL = max(status.remainingWaterL - 0.07, 0)
        status.profileIndex = min(
            Int(status.elapsedKm / plan.route.distanceKm * Double(plan.route.elevationProfile.count - 1)),
            plan.route.elevationProfile.count - 1)
        status.planDeltaMin -= 2
        status.upcomingLongDescent = status.profileIndex >= 22 && status.profileIndex <= 26

        // 触发规则（演示节奏）
        if status.profileIndex >= 24 && lastDecision?.verdict != .downgrade && lastDecision?.verdict != .retreat {
            triggerCheckin(.beforeDescent)
        } else if status.hoursToSunset <= 3 && status.hoursToSunset > 2.7 {
            triggerCheckin(.sunset)
        } else if status.elapsedHours >= 1.6 && status.elapsedHours < 1.9 {
            triggerCheckin(.timer)
        } else if status.planDeltaMin <= -30 && status.planDeltaMin > -36 && status.profileIndex > 8 {
            triggerCheckin(.slowProgress)
        }
    }

    private func triggerCheckin(_ t: CheckinTrigger) {
        guard activeCheckin == nil else { return }
        withAnimation(.spring(duration: 0.5)) { activeCheckin = t }
        Haptics.notify()
    }

    // MARK: 三问提交

    func submitCheckin(water: Double, knee: Double, drowsy: Double) {
        status.remainingWaterL = water
        status.kneePain = knee
        status.drowsiness = drowsy
        let decision = AgentEngine.evaluate(status: status, plan: plan)
        lastDecision = decision
        withAnimation(.spring(duration: 0.5)) {
            activeCheckin = nil
            if decision.verdict == .downgrade || decision.verdict == .retreat {
                showRetreatSheet = true
            }
        }
    }

    private func hoursUntilSunset() -> Double {
        guard let sunset = plan.sunsetTime, let dep = plan.departureTime else { return 8 }
        return max(sunset.timeIntervalSince(dep) / 3600 - 1, 4)
    }
}

enum Haptics {
    static func notify() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
