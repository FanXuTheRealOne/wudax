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

    // 行中
    @Published var activeCheckin: CheckinTrigger?
    @Published var lastDecision: AgentDecision?
    @Published var showRetreatSheet = false
    @Published var tripEndedByRetreat = false
    @Published var routeMatch: RouteMatch?
    @Published var routeImportMessage: String?
    @Published var locationStatusText: String?

    // 复盘
    @Published var reviewEntries = SampleData.reviewQuestions

    private var timer: AnyCancellable?
    private var liveCheckinTimer: AnyCancellable?
    private let locationService = HikeLocationService()
    private var locationCancellable: AnyCancellable?
    private var locationStatusCancellable: AnyCancellable?
    private var routeMatcher: RouteMatchingEngine?
    private var tripStartedAt: Date?
    private var lastCheckinAt: Date?
    private var lastCheckinProgressMeters: Double = 0

    init() {
        locationCancellable = locationService.$latestLocation
            .compactMap { $0 }
            .sink { [weak self] location in self?.handle(location: location) }
        locationStatusCancellable = locationService.$errorMessage
            .sink { [weak self] message in self?.locationStatusText = message }

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
        phase = .planningChat
    }

    func importGPX(from url: URL) {
        do {
            let result = try GPXRouteImporter().load(from: url)
            var importedPlan = TripPlan(route: result.route)
            importedPlan.riskLevel = (result.route.ascentM >= 1_200 || result.route.estimatedHours >= 8) ? .mediumHigh : .medium
            importedPlan.suggestedWaterL = max(1.5, min(5.0, result.route.estimatedHours * profile.waterRatePerHour + 0.5))
            importedPlan.suggestedFoodKcal = max(800, result.route.estimatedHours * 170)
            importedPlan.topRisks = routeRisks(for: result.route)
            importedPlan.checkpoints = result.route.geometry?.waypoints.map(\.name) ?? []
            plan = importedPlan
            routeMatcher = result.route.geometry.map { RouteMatchingEngine(route: $0) }
            routeMatch = nil

            let warningText = result.warnings.isEmpty ? "" : "\n" + result.warnings.joined(separator: "；")
            routeImportMessage = "已导入 \(result.pointCount) 个轨迹点、\(result.waypointCount) 个航点。\(warningText)"
        } catch {
            routeImportMessage = "导入失败：\(error.localizedDescription)"
        }
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
        routeMatch = nil
        lastDecision = nil
        tripStartedAt = Date()
        lastCheckinAt = tripStartedAt
        lastCheckinProgressMeters = 0
        withAnimation { phase = .inTrip }
        if plan.route.geometry != nil {
            routeMatcher = plan.route.geometry.map { RouteMatchingEngine(route: $0) }
            locationService.startTracking()
            startLiveCheckins()
        } else {
            startSimulation()
        }
    }

    func endTrip(retreated: Bool) {
        stopSimulation()
        stopLiveCheckins()
        locationService.stopTracking()
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

    private func handle(location: CLLocation) {
        guard phase == .inTrip, let routeMatcher else { return }
        let match = routeMatcher.match(location: location)
        routeMatch = match
        status.routeConfidence = match.confidence
        status.isOffRoute = match.isOffRoute
        status.routeMatchReason = match.reason
        status.elapsedKm = match.routeProgressMeters / 1_000
        if let tripStartedAt {
            status.elapsedHours = max(0, Date().timeIntervalSince(tripStartedAt) / 3_600)
        }
        status.hoursToSunset = hoursUntilSunset()

        let profileCount = plan.route.elevationProfile.count
        if profileCount > 1, plan.route.distanceKm > 0 {
            status.profileIndex = min(profileCount - 1, max(0, Int((status.elapsedKm / plan.route.distanceKm) * Double(profileCount - 1))))
        }
        status.upcomingLongDescent = match.remainingAscentMeters < 50 && match.remainingDistanceMeters > 1_000

        if match.isOffRoute, activeCheckin == nil, !showRetreatSheet {
            triggerCheckin(.offRoute)
        } else if match.routeProgressMeters - lastCheckinProgressMeters >= 3_000,
                  activeCheckin == nil,
                  !showRetreatSheet {
            triggerCheckin(.timer)
        }
    }

    private func startLiveCheckins() {
        liveCheckinTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self,
                      self.phase == .inTrip,
                      self.activeCheckin == nil,
                      !self.showRetreatSheet,
                      let lastCheckinAt = self.lastCheckinAt,
                      Date().timeIntervalSince(lastCheckinAt) >= 45 * 60 else { return }
                self.triggerCheckin(.timer)
            }
    }

    private func stopLiveCheckins() {
        liveCheckinTimer?.cancel()
        liveCheckinTimer = nil
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
        lastCheckinAt = Date()
        lastCheckinProgressMeters = routeMatch?.routeProgressMeters ?? status.elapsedKm * 1_000
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

    private func routeRisks(for route: Route) -> [String] {
        var risks: [String] = []
        if route.ascentM >= 1_000 { risks.append("累计爬升 \(Int(route.ascentM)) m，体能消耗较高") }
        if route.estimatedHours >= 8 { risks.append("预计行程 \(String(format: "%.1f", route.estimatedHours)) 小时，需要预留返程缓冲") }
        if route.waterSourceCount == 0 { risks.append("GPX 未验证补水点，请自行确认补给与撤离点") }
        return risks
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
