import Foundation
import SwiftUI
import Combine
import CoreLocation

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
    let planning = PlanningCoordinator()
    @Published var planningResult: PlanningResult?
    let location = LocationService()
    let offlineResources = OfflineResourceManager()
    let notifications = NotificationService()
    @Published var events: [TripEvent] = []

    // 行中
    @Published var activeCheckin: CheckinTrigger?
    @Published var lastDecision: AgentDecision?
    @Published var showRetreatSheet = false
    @Published var tripEndedByRetreat = false

    // 复盘
    @Published var reviewEntries = SampleData.reviewQuestions

    private var riskTimer: AnyCancellable?
    private var tripStartDate: Date?

    init() {
        location.onLocationUpdate = { [weak self] location in
            self?.handleLocation(location)
        }
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
        planning.reset()
        planningResult = nil
        phase = .planningChat
    }

    func finalizePlanning() {
        guard let result = planning.buildPlan(profile: profile) else { return }
        planningResult = result
        plan.route = result.route
        plan.readinessScore = result.readiness.score
        plan.readinessLabel = result.readiness.label
        plan.challengeGapLabel = result.gap.label
        plan.routeQualityScore = planning.analyzedGPX?.qualityScore ?? 100
        plan.equipment = result.equipment
        plan.suggestedWaterL = result.supply.waterLiters
        plan.suggestedFoodKcal = result.supply.foodKilocalories
        plan.riskLevel = result.gap.score >= 4 ? .high : result.load.score >= 5 ? .mediumHigh : .medium
        plan.topRisks = Array((result.load.reasons + result.gap.reasons + result.readiness.reasons).prefix(3))
        plan.checkpoints = result.route.riskPoints.map { "\($0.title) · 到达前重新确认状态" }
        if let analyzed = planning.analyzedGPX { offlineResources.prepare(analyzedGPX: analyzed) }
        phase = .budgetCard
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
        tripStartDate = Date()
        events = []
        withAnimation { phase = .inTrip }
        location.startMonitoring()
        Task { await notifications.requestAuthorization() }
        startMonitoring()
    }

    func endTrip(retreated: Bool) {
        stopMonitoring()
        location.stopMonitoring()
        tripEndedByRetreat = retreated
        activeCheckin = nil
        showRetreatSheet = false
        withAnimation { phase = .review }
    }

    func finishReview() {
        let answers = Dictionary(uniqueKeysWithValues: reviewEntries.compactMap { entry in
            entry.answer.map { (entry.question, $0) }
        })
        HikingRuleTools.updatePersonalBaseline(profile: &profile, status: status, reviewAnswers: answers)
        reviewEntries = SampleData.reviewQuestions
        withAnimation { phase = .home }
    }

    // MARK: 行中监测：定位事件 + 前台最多每 30 秒一次规则重算

    private func startMonitoring() {
        riskTimer = Timer.publish(every: 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.evaluateActiveStatus() }
    }

    private func stopMonitoring() { riskTimer?.cancel(); riskTimer = nil }

    private func evaluateActiveStatus() {
        guard phase == .inTrip, activeCheckin == nil, !showRetreatSheet else { return }
        if let tripStartDate { status.elapsedHours = Date().timeIntervalSince(tripStartDate) / 3600 }
        status.hoursToSunset = max(hoursUntilSunset() - status.elapsedHours, 0)
        status.remainingWaterL = max((plan.waterL ?? status.remainingWaterL) - status.elapsedHours * profile.waterRatePerHour, 0)
        status.upcomingLongDescent = status.profileIndex >= 22 && status.profileIndex <= 26

        let risk = HikingRuleTools.evaluateFatigueRisk(status: status, plan: plan)
        let action = HikingRuleTools.selectControlledAction(risk: risk, status: status, plan: plan)
        if risk.level == .high || risk.level == .mediumHigh {
            lastDecision = AgentDecision(verdict: risk.level == .high ? .retreat : .downgrade,
                                         reasons: risk.reasons, watchHint: action.title, detail: action.detail)
        }

        if status.profileIndex >= 24 && lastDecision?.verdict != .downgrade && lastDecision?.verdict != .retreat {
            triggerCheckin(.beforeDescent)
        } else if status.hoursToSunset <= 3 && status.hoursToSunset > 2.5 {
            triggerCheckin(.sunset)
        } else if status.elapsedHours >= 1.5 && status.elapsedHours < 1.6 {
            triggerCheckin(.timer)
        } else if status.planDeltaMin <= -30 && status.profileIndex > 8 {
            triggerCheckin(.slowProgress)
        }
    }

    private func handleLocation(_ location: CLLocation) {
        guard phase == .inTrip, let analyzed = planning.analyzedGPX,
              let progress = HikingRuleTools.matchRouteProgress(document: analyzed.document,
                                                                 latitude: location.coordinate.latitude,
                                                                 longitude: location.coordinate.longitude) else { return }
        status.elapsedKm = progress.fractionComplete * plan.route.distanceKm
        status.profileIndex = min(Int(progress.fractionComplete * Double(max(plan.route.elevationProfile.count - 1, 0))),
                                  max(plan.route.elevationProfile.count - 1, 0))
        status.upcomingLongDescent = status.profileIndex >= max(plan.route.elevationProfile.count - 5, 0)
        if progress.distanceToRouteMeters > 120 {
            events.append(.init(date: Date(), title: "偏离已导入路线", detail: "当前位置距路线约 \(Int(progress.distanceToRouteMeters)) m", risk: .mediumHigh))
            triggerCheckin(.keypoint)
        }
        evaluateActiveStatus()
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
        let risk = HikingRuleTools.evaluateFatigueRisk(status: status, plan: plan)
        let action = HikingRuleTools.selectControlledAction(risk: risk, status: status, plan: plan)
        notifications.postIfNeeded(risk: risk, action: action)
        events.append(.init(date: Date(), title: decision.verdict.rawValue, detail: decision.reasons.joined(separator: "；"), risk: risk.level))
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
