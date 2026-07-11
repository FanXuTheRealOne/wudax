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
    let recorder = TripTrackRecorder()
    let offlineResources = OfflineResourceManager()
    let notifications = NotificationService()
    let tripStore = TripStore()
    /// 本地路线库(历史 GPX 记录),由 App 注入。
    var library: RouteLibraryStore?
    @Published var events: [TripEvent] = []
    @Published var latestHealthSnapshot: HealthSnapshot?
    @Published private(set) var preparedRoute: PreparedGPXRoute?
    @Published private(set) var routeMatch: RouteMatchResult?

    // 行中
    @Published var activeCheckin: CheckinTrigger?
    @Published var lastDecision: AgentDecision?
    @Published var showRetreatSheet = false
    @Published var tripEndedByRetreat = false

    // 复盘
    @Published var reviewEntries = SampleData.reviewQuestions

    private var riskTimer: AnyCancellable?
    private var planningCancellable: AnyCancellable?
    private var tripStartDate: Date?
    private var currentTripID = UUID()
    private var lastRiskLevel: RiskLevel = .low
    private var lastOffRouteEventAt: Date?
    private var routeMatcher: GPXRouteMatcher?
    private var lastRouteLocationAt: Date?
    /// 当前规划来源于哪条已存记录(为空表示是新导入,完成后入库)。
    private var planningSourceRecordID: UUID?

    init() {
        location.onLocationUpdate = { [weak self] location in
            self?.handleLocation(location)
        }
        planning.healthKit.onSnapshotUpdate = { [weak self] snapshot in
            self?.handleHealthSnapshot(snapshot)
        }
        // PlanningCoordinator is a nested ObservableObject. Forward its
        // changes so SwiftUI views observing TripSession redraw immediately
        // when a planning answer (health history, GPX, or questionnaire) is
        // selected.
        planningCancellable = planning.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
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
        preparedRoute = nil
        routeMatcher = nil
        routeMatch = nil
        lastRouteLocationAt = nil
        planningSourceRecordID = nil
        phase = .planningChat
    }

    /// 从历史路线库里选一条已存记录进入规划(路线已载入,无需重新导入)。
    func planRecord(_ record: RouteRecord) {
        plan = SampleData.plan
        planning.reset()
        planningResult = nil
        preparedRoute = nil
        routeMatcher = nil
        routeMatch = nil
        lastRouteLocationAt = nil
        planningSourceRecordID = record.id
        planning.loadForPlanning(record)
        phase = .planningChat
    }

    func finalizePlanning() {
        guard let result = planning.buildPlan(profile: profile) else { return }
        planningResult = result
        plan.route = result.route
        plan.readinessLabel = result.comparison.difficultyLabel
        plan.challengeGapLabel = result.comparison.difficultyLabel
        plan.routeQualityScore = planning.analyzedGPX?.qualityScore ?? 100
        plan.equipment = result.equipment
        plan.suggestedWaterL = result.supply.waterLiters
        plan.suggestedFoodKcal = result.supply.foodKilocalories
        plan.riskLevel = result.comparison.riskLevel
        plan.topRisks = Array(result.comparison.analysis.prefix(3))
        plan.checkpoints = result.route.riskPoints.map { "\($0.title) · 到达前重新确认状态" }
        if let analyzed = planning.analyzedGPX,
           let prepared = try? GPXRoutePreprocessor().prepare(analyzed.document.copyForPlanning()) {
            preparedRoute = prepared
            routeMatcher = GPXRouteMatcher(route: prepared)
            offlineResources.prepare(analyzedGPX: analyzed, preparedRoute: prepared,
                                     originalGPXData: planning.importedGPXData)
        }
        // 新导入的路线完成规划后写入本地库(从已存记录进入的不重复入库)。
        if planningSourceRecordID == nil, let analyzed = planning.analyzedGPX {
            library?.upsert(RouteRecord(analyzedGPX: analyzed, createdAt: Date()))
        }
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
        // Stage 1 只有在 GPX、HealthKit/问卷和补给问题全部齐备后，
        // 由聊天流中的“生成行前报告”显式进入预算卡。
    }

    func confirmBudget() { withAnimation { phase = .gate } }

    func depart() {
        status = TripStatus()
        status.remainingWaterL = plan.waterL ?? plan.suggestedWaterL
        status.hoursToSunset = hoursUntilSunset()
        tripStartDate = Date()
        currentTripID = UUID()
        events = []
        lastRiskLevel = .low
        lastOffRouteEventAt = nil
        routeMatch = nil
        lastRouteLocationAt = nil
        if let preparedRoute {
            routeMatcher = GPXRouteMatcher(route: preparedRoute)
        } else if let analyzed = planning.analyzedGPX,
                  let prepared = try? GPXRoutePreprocessor().prepare(analyzed.document.copyForPlanning()) {
            preparedRoute = prepared
            routeMatcher = GPXRouteMatcher(route: prepared)
        }
        recorder.start()
        withAnimation { phase = .inTrip }
        location.startMonitoring()
        Task {
            _ = await notifications.requestAuthorization()
            // 行中实时读取手表 / 苹果健康数据
            _ = await planning.requestHealthAuthorization()
            latestHealthSnapshot = planning.healthSnapshot
        }
        startMonitoring()
    }

    func endTrip(retreated: Bool) {
        stopMonitoring()
        location.stopMonitoring()
        recorder.stop()
        persistTrip()
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
        persistTrip()
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
        let now = Date()
        if let tripStartDate { status.elapsedHours = now.timeIntervalSince(tripStartDate) / 3600 }
        if let routeMatcher,
           lastRouteLocationAt.map({ now.timeIntervalSince($0) >= 15 }) ?? false {
            applyRouteMatch(routeMatcher.locationUnavailable(at: now,
                                                             cadenceStepsPerMinute: nil),
                            allowOffRouteAlert: false)
        }
        status.hoursToSunset = max(hoursUntilSunset() - status.elapsedHours, 0)
        status.remainingWaterL = max((plan.waterL ?? status.remainingWaterL) - status.elapsedHours * profile.waterRatePerHour, 0)
        if plan.route.estimatedHours > 0 {
            let expectedFraction = min(status.elapsedHours / plan.route.estimatedHours, 1)
            let actualFraction = plan.route.distanceKm > 0 ? min(status.elapsedKm / plan.route.distanceKm, 1) : 0
            status.planDeltaMin = Int(((actualFraction - expectedFraction) * plan.route.estimatedHours * 60).rounded())
        }
        status.upcomingLongDescent = status.profileIndex >= 22 && status.profileIndex <= 26

        let risk = HikingRuleTools.evaluateFatigueRisk(status: status, plan: plan, snapshot: latestHealthSnapshot)
        let action = HikingRuleTools.selectControlledAction(risk: risk, status: status, plan: plan)
        if risk.level.rank > lastRiskLevel.rank {
            lastRiskLevel = risk.level
            lastDecision = AgentDecision(verdict: risk.level == .high ? .retreat : .downgrade,
                                         reasons: risk.reasons, watchHint: action.title, detail: action.detail)
            events.append(.init(date: Date(), title: "主动风险升级", detail: risk.reasons.joined(separator: "；"), risk: risk.level))
            notifications.postIfNeeded(risk: risk, action: action)
        }

        if risk.level.rank >= RiskLevel.mediumHigh.rank && activeCheckin == nil {
            triggerCheckin(.slowProgress)
        } else if status.profileIndex >= 24 && lastDecision?.verdict != .downgrade && lastDecision?.verdict != .retreat {
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
        recorder.append(location)
        guard phase == .inTrip, let routeMatcher else { return }
        let input = RouteLocationInput(
            coordinate: RouteCoordinate(latitude: location.coordinate.latitude,
                                        longitude: location.coordinate.longitude),
            horizontalAccuracyMeters: location.horizontalAccuracy,
            timestamp: location.timestamp,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            courseDegrees: location.course >= 0 ? location.course : nil,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            cadenceStepsPerMinute: nil
        )
        lastRouteLocationAt = location.timestamp
        applyRouteMatch(routeMatcher.match(input), allowOffRouteAlert: true)
        evaluateActiveStatus()
    }

    private func applyRouteMatch(_ match: RouteMatchResult, allowOffRouteAlert: Bool) {
        routeMatch = match
        let statusProgressMeters: Double = switch match.confidence {
        case .high, .medium: match.routeProgressMeters
        case .low, .none: match.lastReliableProgressMeters
        }
        status.elapsedKm = statusProgressMeters / 1_000
        let totalDistance = preparedRoute?.totalDistanceMeters ?? max(plan.route.distanceKm * 1_000, 1)
        let fractionComplete = min(max(statusProgressMeters / max(totalDistance, 1), 0), 1)
        if plan.route.estimatedHours > 0 {
            let expectedFraction = min(status.elapsedHours / plan.route.estimatedHours, 1)
            status.planDeltaMin = Int(((fractionComplete - expectedFraction) * plan.route.estimatedHours * 60).rounded())
        }
        status.profileIndex = min(Int(fractionComplete * Double(max(plan.route.elevationProfile.count - 1, 0))),
                                  max(plan.route.elevationProfile.count - 1, 0))
        status.upcomingLongDescent = status.profileIndex >= max(plan.route.elevationProfile.count - 5, 0)
        let now = Date()
        let canRecordOffRouteEvent = lastOffRouteEventAt.map { now.timeIntervalSince($0) >= 5 * 60 } ?? true
        if allowOffRouteAlert, match.isOffRoute, canRecordOffRouteEvent {
            lastOffRouteEventAt = now
            events.append(.init(date: now, title: "可能偏离已导入路线",
                                detail: "距路线约 \(Int(match.distanceToRouteMeters.rounded())) m；\(match.reason)",
                                risk: .mediumHigh))
            notifications.postRouteDeviationIfNeeded(match, now: now)
            triggerCheckin(.offRoute)
        }
    }

    private func handleHealthSnapshot(_ snapshot: HealthSnapshot) {
        latestHealthSnapshot = snapshot
        guard phase == .inTrip else { return }
        evaluateActiveStatus()
    }

    private func triggerCheckin(_ t: CheckinTrigger) {
        guard activeCheckin == nil else { return }
        withAnimation(.spring(duration: 0.5)) { activeCheckin = t }
        Haptics.notify()
    }

    // MARK: 三问提交

    func submitCheckin(fatigue: Double, water: Double, supplyRatio: Double) {
        status.subjectiveFatigue = fatigue
        status.drowsiness = fatigue   // 复用为疲劳信号供规则引擎评估
        status.remainingWaterL = water
        status.remainingSupplyRatio = supplyRatio
        let decision = AgentEngine.evaluate(status: status, plan: plan)
        lastDecision = decision
        let risk = HikingRuleTools.evaluateFatigueRisk(status: status, plan: plan, snapshot: latestHealthSnapshot)
        let action = HikingRuleTools.selectControlledAction(risk: risk, status: status, plan: plan)
        if risk.level.rank > lastRiskLevel.rank { lastRiskLevel = risk.level }
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

    private func persistTrip() {
        let answers = Dictionary(uniqueKeysWithValues: reviewEntries.compactMap { entry in
            entry.answer.map { (entry.question, $0) }
        })
        let challenge = HikingRuleTools.calculateChallengeGap(route: plan.route, profile: profile,
                                                               readiness: .init(score: plan.readinessScore, label: plan.readinessLabel,
                                                                                reasons: [], missingInputs: []))
        let advice = HikingRuleTools.buildTrainingAdvice(profile: profile, challenge: challenge)
        let peak = events.map(\.risk).max(by: { $0.rank < $1.rank }) ?? .low
        let stored = StoredTrip(id: currentTripID, completedAt: Date(), route: planning.analyzedGPX?.document,
                                summary: HikingRuleTools.summarizeTrip(plan: plan, status: status, peakRisk: peak,
                                                                        keyEvents: events.map(\.title)),
                                events: events, reviewAnswers: answers, trainingAdvice: advice,
                                recordedTrack: recorder.points)
        tripStore.save(stored)
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
