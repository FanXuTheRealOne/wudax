import Foundation

// MARK: - Agent 数据总线
// 把 TripSession / 路线匹配 / HealthKit / 路线库 / 行走 log 的全部数据
// 组装成给本地 LLM 的结构化中文快照(0.6B 模型对分节中文文本的理解优于 JSON)。
// 安全结论永远来自规则引擎;快照只负责把事实完整暴露给表达层。

// MARK: 前方路线前瞻

/// 从预处理路线 + 当前进度计算「路线的未来情况」:前方坡度/爬升、分段概览、下一航点、将到的风险点。
struct RouteLookahead: Equatable {
    struct Upcoming: Equatable {
        var title: String
        var distanceMeters: Double
    }

    var nextKmAscentMeters: Double
    var nextKmDescentMeters: Double
    var nextKmAvgGradePercent: Double?
    /// 每 2 km 一句的后续路段概览(最多 4 段)。
    var segmentSummaries: [String]
    var nextWaypoint: Upcoming?
    /// 前方(尚未经过的)风险点,按距离升序。
    var upcomingRiskPoints: [Upcoming]

    static func compute(route: PreparedGPXRoute,
                        progressMeters: Double,
                        riskPoints: [(title: String, progressMeters: Double)],
                        maxSegments: Int = 4) -> RouteLookahead {
        let vertices = route.vertices
        guard vertices.count >= 2 else {
            return RouteLookahead(nextKmAscentMeters: 0, nextKmDescentMeters: 0,
                                  nextKmAvgGradePercent: nil, segmentSummaries: [],
                                  nextWaypoint: nil, upcomingRiskPoints: [])
        }

        let (ascent1km, descent1km) = elevationChange(vertices: vertices,
                                                      from: progressMeters,
                                                      to: progressMeters + 1_000)
        let horizontal = min(1_000, max(route.totalDistanceMeters - progressMeters, 1))
        let net = netElevationChange(vertices: vertices, from: progressMeters, to: progressMeters + 1_000)
        let grade: Double? = net.map { ($0 / horizontal) * 100 }

        var summaries: [String] = []
        var cursor = progressMeters
        while cursor < route.totalDistanceMeters, summaries.count < maxSegments {
            let end = min(cursor + 2_000, route.totalDistanceMeters)
            let (up, down) = elevationChange(vertices: vertices, from: cursor, to: end)
            let range = String(format: "%.1f–%.1f km", cursor / 1_000, end / 1_000)
            summaries.append("\(range):\(describe(ascent: up, descent: down))")
            cursor = end
        }

        let nextWaypoint = route.waypoints
            .filter { $0.routeProgressMeters > progressMeters }
            .min { $0.routeProgressMeters < $1.routeProgressMeters }
            .map { Upcoming(title: $0.name ?? "未命名航点",
                            distanceMeters: $0.routeProgressMeters - progressMeters) }

        let upcomingRisks = riskPoints
            .filter { $0.progressMeters > progressMeters }
            .sorted { $0.progressMeters < $1.progressMeters }
            .map { Upcoming(title: $0.title, distanceMeters: $0.progressMeters - progressMeters) }

        return RouteLookahead(nextKmAscentMeters: ascent1km,
                              nextKmDescentMeters: descent1km,
                              nextKmAvgGradePercent: grade,
                              segmentSummaries: summaries,
                              nextWaypoint: nextWaypoint,
                              upcomingRiskPoints: upcomingRisks)
    }

    /// 区间内正向爬升与下降的累计值。
    private static func elevationChange(vertices: [PreparedRouteVertex],
                                        from: Double, to: Double) -> (ascent: Double, descent: Double) {
        var ascent = 0.0, descent = 0.0
        var previous: Double?
        for vertex in vertices {
            guard vertex.cumulativeDistanceMeters >= from else { continue }
            guard vertex.cumulativeDistanceMeters <= to else { break }
            guard let elevation = vertex.elevationMeters else { continue }
            if let prev = previous {
                let delta = elevation - prev
                if delta > 0 { ascent += delta } else { descent -= delta }
            }
            previous = elevation
        }
        return (ascent, descent)
    }

    private static func netElevationChange(vertices: [PreparedRouteVertex],
                                           from: Double, to: Double) -> Double? {
        let inRange = vertices.filter { $0.cumulativeDistanceMeters >= from && $0.cumulativeDistanceMeters <= to }
        guard let first = inRange.first?.elevationMeters, let last = inRange.last?.elevationMeters else { return nil }
        return last - first
    }

    private static func describe(ascent: Double, descent: Double) -> String {
        switch (ascent, descent) {
        case let (up, down) where up < 30 && down < 30: return "较平缓"
        case let (up, down) where up >= down && up >= 150: return "陡升 \(Int(up)) m"
        case let (up, down) where up >= down: return "缓升 \(Int(up)) m"
        case let (_, down) where down >= 150: return "陡降 \(Int(down)) m(注意膝盖)"
        default: return "缓降 \(Int(descent)) m"
        }
    }
}

// MARK: 主动播报信号

/// 一次值得 agent 主动开口的状态变化。
enum AgentSignal: Equatable {
    case sessionStart
    case verdictChanged(AgentVerdict)
    case offRouteChanged(isOff: Bool, distanceMeters: Double)
    case heartRateShift(bpm: Double, baselineBPM: Double?)
    case paceBandChanged(planDeltaMin: Int)
    case sunsetWindow(hoursLeft: Double)
    case upcomingRiskPoint(title: String, distanceMeters: Double)
    case progressMilestone(percent: Int)

    /// 冷却与去重用的稳定 key。
    var key: String {
        switch self {
        case .sessionStart: "sessionStart"
        case .verdictChanged: "verdict"
        case .offRouteChanged: "offRoute"
        case .heartRateShift: "heartRate"
        case .paceBandChanged: "pace"
        case .sunsetWindow: "sunset"
        case .upcomingRiskPoint(let title, _): "risk:\(title)"
        case .progressMilestone(let p): "milestone:\(p)"
        }
    }

    var headline: String {
        switch self {
        case .sessionStart: "行程开始"
        case .verdictChanged(let v): "状态判级:\(v.rawValue)"
        case .offRouteChanged(let isOff, _): isOff ? "可能偏离路线" : "已回到路线"
        case .heartRateShift: "心率变化"
        case .paceBandChanged: "配速变化"
        case .sunsetWindow: "日落余量"
        case .upcomingRiskPoint(let title, _): "前方:\(title)"
        case .progressMilestone(let p): "进度 \(p)%"
        }
    }
}

/// 信号检测的输入(从 TripSession 采样成纯值,便于测试)。
struct AgentSignalInput {
    var isRecording = false
    var verdict: AgentVerdict?
    var isOffRoute = false
    var distanceToRouteMeters: Double = 0
    var heartRateBPM: Double?
    var planDeltaMin = 0
    var hoursToSunset: Double = 8
    var progressFraction: Double = 0
    var upcomingRisk: (title: String, distanceMeters: Double)?
}

/// 每个 session context 独立持有的信号记忆(变化检测 + 冷却)。
struct AgentSignalMemory {
    var didAnnounceStart = false
    var lastVerdict: AgentVerdict?
    var lastOffRoute = false
    var heartRateBaselineBPM: Double?
    var baselineSampleCount = 0
    var lastAnnouncedHeartRateBand: Int?
    var lastPaceBand = 0
    var lastSunsetBand = 0
    var announcedMilestones: Set<Int> = []
    var announcedRiskKeys: Set<String> = []
    var lastFiredAt: [String: Date] = [:]
    var lastGlobalFiredAt: Date?
}

enum AgentSignalDetector {
    static let signalCooldown: TimeInterval = 8 * 60
    static let globalCooldown: TimeInterval = 90
    /// 前 N 个心率样本取均值作为 session 基线。
    static let baselineSamples = 5
    static let heartRateShiftThreshold: Double = 15
    static let highHeartRate: Double = 150

    /// 喂一个心率样本,维护 session 基线。
    static func recordHeartRate(_ bpm: Double, memory: inout AgentSignalMemory) {
        guard memory.baselineSampleCount < baselineSamples else { return }
        let count = Double(memory.baselineSampleCount)
        let base = memory.heartRateBaselineBPM ?? 0
        memory.heartRateBaselineBPM = (base * count + bpm) / (count + 1)
        memory.baselineSampleCount += 1
    }

    /// 检测最优先的一条应播报信号;命中即更新记忆与冷却。
    static func detect(input: AgentSignalInput,
                       memory: inout AgentSignalMemory,
                       now: Date = Date()) -> AgentSignal? {
        guard input.isRecording else { return nil }

        // 开场播报不受全局冷却限制。
        if !memory.didAnnounceStart {
            memory.didAnnounceStart = true
            return fire(.sessionStart, memory: &memory, now: now)
        }

        if let last = memory.lastGlobalFiredAt, now.timeIntervalSince(last) < globalCooldown {
            return nil
        }

        // 优先级:判级 > 偏航 > 心率 > 日落 > 前方风险点 > 配速 > 里程碑
        if let verdict = input.verdict, verdict != memory.lastVerdict {
            let previous = memory.lastVerdict
            memory.lastVerdict = verdict
            // 首次出现「继续」不值得打扰;有历史值或结论收紧才播报。
            if previous != nil || verdict != .proceed {
                if cooled("verdict", memory: memory, now: now) {
                    return fire(.verdictChanged(verdict), memory: &memory, now: now)
                }
            }
        }

        if input.isOffRoute != memory.lastOffRoute {
            memory.lastOffRoute = input.isOffRoute
            if cooled("offRoute", memory: memory, now: now) {
                return fire(.offRouteChanged(isOff: input.isOffRoute,
                                             distanceMeters: input.distanceToRouteMeters),
                            memory: &memory, now: now)
            }
        }

        if let hr = input.heartRateBPM {
            let baseline = memory.heartRateBaselineBPM
            let shifted = baseline.map { abs(hr - $0) >= heartRateShiftThreshold } ?? false
            let band = Int(hr / 10)
            if (shifted || hr >= highHeartRate), band != memory.lastAnnouncedHeartRateBand,
               cooled("heartRate", memory: memory, now: now) {
                memory.lastAnnouncedHeartRateBand = band
                return fire(.heartRateShift(bpm: hr, baselineBPM: baseline), memory: &memory, now: now)
            }
        }

        let sunsetBand = input.hoursToSunset < 2 ? 2 : input.hoursToSunset < 3 ? 1 : 0
        if sunsetBand > memory.lastSunsetBand {
            memory.lastSunsetBand = sunsetBand
            if cooled("sunset", memory: memory, now: now) {
                return fire(.sunsetWindow(hoursLeft: input.hoursToSunset), memory: &memory, now: now)
            }
        }

        if let risk = input.upcomingRisk, risk.distanceMeters <= 600 {
            let signal = AgentSignal.upcomingRiskPoint(title: risk.title, distanceMeters: risk.distanceMeters)
            if !memory.announcedRiskKeys.contains(signal.key) {
                memory.announcedRiskKeys.insert(signal.key)
                return fire(signal, memory: &memory, now: now)
            }
        }

        let paceBand = input.planDeltaMin <= -40 ? 2 : input.planDeltaMin <= -20 ? 1 : 0
        if paceBand > memory.lastPaceBand {
            memory.lastPaceBand = paceBand
            if cooled("pace", memory: memory, now: now) {
                return fire(.paceBandChanged(planDeltaMin: input.planDeltaMin), memory: &memory, now: now)
            }
        } else if paceBand < memory.lastPaceBand {
            memory.lastPaceBand = paceBand   // 恢复不播报,只更新记忆
        }

        for milestone in [25, 50, 75] where Int(input.progressFraction * 100) >= milestone
            && !memory.announcedMilestones.contains(milestone) {
            memory.announcedMilestones.insert(milestone)
            return fire(.progressMilestone(percent: milestone), memory: &memory, now: now)
        }

        return nil
    }

    private static func cooled(_ key: String, memory: AgentSignalMemory, now: Date) -> Bool {
        guard let last = memory.lastFiredAt[key] else { return true }
        return now.timeIntervalSince(last) >= signalCooldown
    }

    private static func fire(_ signal: AgentSignal,
                             memory: inout AgentSignalMemory,
                             now: Date) -> AgentSignal {
        memory.lastFiredAt[signal.key] = now
        memory.lastGlobalFiredAt = now
        return signal
    }
}

// MARK: 快照组装

@MainActor
enum AgentDataBus {

    /// 全量快照:问答时注入,尽可能暴露所有真实数据。
    static func fullSnapshot(session: TripSession) -> String {
        var sections: [String] = []
        sections.append(routeSection(session))
        if let risks = riskPointSection(session) { sections.append(risks) }
        if let prov = provenanceSection(session) { sections.append(prov) }
        sections.append(profileSection(session))
        sections.append(planSection(session))
        sections.append(liveSection(session))
        if let ahead = lookaheadSection(session) { sections.append(ahead) }
        if let health = healthSection(session) { sections.append(health) }
        sections.append(supplySection(session))
        sections.append(safetySection(session))
        if let events = eventsSection(session) { sections.append(events) }
        if let history = historySection(session) { sections.append(history) }
        return sections.joined(separator: "\n")
    }

    /// 精简快照:主动播报时附带,控制生成延迟。
    static func compactSnapshot(session: TripSession) -> String {
        var sections = [liveSection(session)]
        if let ahead = lookaheadSection(session) { sections.append(ahead) }
        if let health = healthSection(session) { sections.append(health) }
        sections.append(safetySection(session))
        return sections.joined(separator: "\n")
    }

    /// 路线风险点换算成沿线里程(profileIndex → 米)。
    static func riskPointProgress(route: Route, totalDistanceMeters: Double) -> [(title: String, progressMeters: Double)] {
        let count = max(route.elevationProfile.count - 1, 1)
        return route.riskPoints.map { point in
            (point.title, Double(point.profileIndex) / Double(count) * totalDistanceMeters)
        }
    }

    /// 当前 lookahead(路线未来情况);未在路线上或无预处理路线时为 nil。
    static func lookahead(session: TripSession) -> RouteLookahead? {
        guard let prepared = session.preparedRoute else { return nil }
        let progress = session.routeMatch?.routeProgressMeters ?? 0
        let risks = riskPointProgress(route: session.plan.route,
                                      totalDistanceMeters: prepared.totalDistanceMeters)
        return RouteLookahead.compute(route: prepared, progressMeters: progress, riskPoints: risks)
    }

    // MARK: 分节

    private static func routeSection(_ s: TripSession) -> String {
        let r = s.plan.route
        var parts = [String(format: "%@:全程 %.1f km,累计爬升 %d m/下降 %d m",
                            r.name, r.distanceKm, Int(r.ascentM), Int(r.descentM))]
        if let maxEle = r.elevationProfile.max() { parts.append("最高海拔 \(Int(maxEle)) m") }
        parts.append(String(format: "按你的经验预计 %.1f 小时", r.estimatedHours))
        if r.isOutAndBack { parts.append("环线/原路返回") }
        parts.append("水源点 \(r.waterSourceCount) 个")
        parts.append("轨迹质量 \(r.qualityScore)/100")
        if r.hasUnverifiedSegment { parts.append("含无路/探路段,撤退点稀少") }
        return "【路线】" + parts.joined(separator: ",")
    }

    private static func riskPointSection(_ s: TripSession) -> String? {
        guard let prepared = s.preparedRoute else { return nil }
        let points = riskPointProgress(route: s.plan.route, totalDistanceMeters: prepared.totalDistanceMeters)
        guard !points.isEmpty else { return nil }
        let text = points.map { String(format: "%@ 在第 %.1f km", $0.title, $0.progressMeters / 1_000) }
        return "【风险点】" + text.joined(separator: ";")
    }

    private static func provenanceSection(_ s: TripSession) -> String? {
        guard let prov = s.plan.route.provenance else { return nil }
        var parts = ["原作者 \(prov.displayAuthor)(不是当前用户,数据仅供参考)"]
        if let date = prov.recordedAt { parts.append("录制于 \(dateText(date))") }
        if let duration = prov.recordedDurationText { parts.append("原作者用时 \(duration)") }
        if let pace = prov.paceText { parts.append("原作者配速 \(pace)") }
        return "【轨迹来源】" + parts.joined(separator: ",")
    }

    private static func profileSection(_ s: TripSession) -> String {
        let exp = s.planning.experience
        let profile = s.profile
        var parts: [String] = []
        if exp.isComplete {
            parts.append(String(format: "走过最难:%.0f km/拔高 %.0f m/最高海拔 %.0f m/用时 %.0f h",
                                exp.hardestDistanceKm, exp.hardestAscentM, exp.highestAltitudeM, exp.longestDurationH))
        }
        parts.append(String(format: "下坡耐受 %.1f km,耗水率 %.2f L/h,已记录 %d 次行程",
                            profile.descentToleranceKm, profile.waterRatePerHour, profile.tripsRecorded))
        return "【用户画像】" + parts.joined(separator: ";")
    }

    private static func planSection(_ s: TripSession) -> String {
        let plan = s.plan
        var parts: [String] = []
        if let dep = plan.departureTime { parts.append("出发 \(timeText(dep))") }
        if let water = plan.waterL {
            parts.append(String(format: "带水 %.1f L(建议 %.1f)", water, plan.suggestedWaterL))
        }
        if let food = plan.foodKcal {
            parts.append("食物 \(Int(food)) kcal(建议 \(Int(plan.suggestedFoodKcal)))")
        }
        if let sunset = plan.sunsetTime { parts.append("日落 \(timeText(sunset))") }
        if !plan.checkpoints.isEmpty { parts.append("复核点:" + plan.checkpoints.joined(separator: "、")) }
        return "【计划】" + parts.joined(separator: ";")
    }

    private static func liveSection(_ s: TripSession) -> String {
        var parts: [String] = []
        switch s.trackingState {
        case .waitingGPS: parts.append("等待 GPS 定位")
        case .toStart(let d): parts.append(String(format: "正在前往路线起点,还差 %@", distanceText(d)))
        case .recording:
            if let start = s.hikeStartDate {
                parts.append("已记录 \(durationText(Date().timeIntervalSince(start)))")
            }
            parts.append(String(format: "已行进 %.1f km", s.status.elapsedKm))
            if let remaining = s.remainingDistanceKm {
                parts.append(String(format: "剩余 %.1f km", remaining))
            }
            if let match = s.routeMatch {
                parts.append("剩余爬升 \(Int(match.remainingAscentMeters)) m")
                parts.append("GPS \(confidenceText(match.confidence))\(match.isOffRoute ? ",可能偏离路线 \(Int(match.distanceToRouteMeters)) m" : ",在路线上")")
            }
            if let eta = s.estimatedFinishDate { parts.append("预计 \(timeText(eta)) 走完") }
            if s.status.planDeltaMin != 0 {
                parts.append(s.status.planDeltaMin < 0 ? "比计划慢 \(-s.status.planDeltaMin) 分钟" : "比计划快 \(s.status.planDeltaMin) 分钟")
            }
            if s.status.elapsedHours > 0.2, s.status.elapsedKm > 0.2 {
                let paceSec = s.status.elapsedHours * 3600 / s.status.elapsedKm
                parts.append("当前配速 \(paceText(paceSec))")
                if let authorPace = s.plan.route.provenance?.paceSecondsPerKm {
                    parts.append("原作者此路线配速 \(paceText(authorPace))")
                }
            }
        }
        parts.append(String(format: "距日落 %.1f 小时", s.status.hoursToSunset))
        return "【实时】" + parts.joined(separator: ";")
    }

    private static func lookaheadSection(_ s: TripSession) -> String? {
        guard case .recording = s.trackingState, let ahead = lookahead(session: s) else { return nil }
        var parts: [String] = []
        if ahead.nextKmAscentMeters >= 20 || ahead.nextKmDescentMeters >= 20 {
            var text = "前方 1 km:"
            if ahead.nextKmAscentMeters >= 20 { text += "爬升 \(Int(ahead.nextKmAscentMeters)) m " }
            if ahead.nextKmDescentMeters >= 20 { text += "下降 \(Int(ahead.nextKmDescentMeters)) m" }
            if let grade = ahead.nextKmAvgGradePercent { text += String(format: "(平均坡度 %.0f%%)", grade) }
            parts.append(text)
        } else {
            parts.append("前方 1 km 较平缓")
        }
        if let risk = ahead.upcomingRiskPoints.first {
            parts.append("距「\(risk.title)」还有 \(distanceText(risk.distanceMeters))")
        }
        if let wp = ahead.nextWaypoint {
            parts.append("下一航点「\(wp.title)」还有 \(distanceText(wp.distanceMeters))")
        }
        if !ahead.segmentSummaries.isEmpty {
            parts.append("后续:" + ahead.segmentSummaries.joined(separator: ";"))
        }
        return "【前方路线】" + parts.joined(separator: "。")
    }

    private static func healthSection(_ s: TripSession) -> String? {
        guard let snapshot = s.latestHealthSnapshot, !snapshot.readings.isEmpty else { return nil }
        let interesting: [(HealthMetric, String)] = [
            (.heartRate, "心率"), (.restingHeartRate, "静息心率"),
            (.heartRateVariability, "HRV"), (.oxygenSaturation, "血氧"),
            (.respiratoryRate, "呼吸率"), (.vo2Max, "VO2Max"),
            (.sleepDuration, "昨夜睡眠"), (.steps, "今日步数"),
            (.activeEnergy, "活动能量"), (.walkingHeartRateAverage, "步行平均心率")
        ]
        var parts: [String] = []
        for (metric, label) in interesting {
            guard let reading = snapshot.reading(metric) else { continue }
            var text = "\(label) \(trimNumber(reading.value))\(reading.unit == "count" ? "" : " " + reading.unit)"
            if reading.freshness == .stale { text += "(数据已过期)" }
            parts.append(text)
        }
        guard !parts.isEmpty else { return nil }
        return "【身体】" + parts.joined(separator: ";")
    }

    private static func supplySection(_ s: TripSession) -> String {
        var parts = [String(format: "剩余水量 %.1f L", s.status.remainingWaterL)]
        parts.append("补给余量约 \(Int(s.status.remainingSupplyRatio * 100))%")
        if s.status.subjectiveFatigue > 0 {
            parts.append("主观疲劳 \(Int(s.status.subjectiveFatigue))/10")
        }
        if s.status.kneePain > 0 { parts.append("膝痛 \(Int(s.status.kneePain))/10") }
        return "【补给与身体感受】" + parts.joined(separator: ";")
    }

    private static func safetySection(_ s: TripSession) -> String {
        let decision = s.lastDecision ?? AgentEngine.evaluate(status: s.status, plan: s.plan)
        let risk = HikingRuleTools.evaluateFatigueRisk(status: s.status, plan: s.plan,
                                                       snapshot: s.latestHealthSnapshot)
        let action = HikingRuleTools.selectControlledAction(risk: risk, status: s.status, plan: s.plan)
        var parts = ["判级「\(decision.verdict.rawValue)」"]
        parts.append("原因:" + decision.reasons.joined(separator: "、"))
        parts.append("建议动作:\(action.title)")
        return "【安全结论(规则引擎,必须以此为准)】" + parts.joined(separator: ";")
    }

    private static func eventsSection(_ s: TripSession) -> String? {
        guard !s.events.isEmpty else { return nil }
        let recent = s.events.suffix(5).map { "\(timeText($0.date)) \($0.title)" }
        return "【最近事件】" + recent.joined(separator: ";")
    }

    private static func historySection(_ s: TripSession) -> String? {
        guard let recordID = s.activeRouteRecordID else { return nil }
        let logs = s.tripStore.trips(forRoute: recordID)
        guard !logs.isEmpty else { return nil }
        var parts = ["你走过这条路线 \(logs.count) 次"]
        if let last = logs.first {
            let outcome = last.endedByRetreat == true ? "中途撤退" : "完成"
            parts.append(String(format: "上次 %@ %@,用时 %.1f 小时,实走 %.1f km",
                                dateText(last.startedAt ?? last.completedAt), outcome,
                                last.summary.actualHours, last.summary.actualDistanceKm))
        }
        return "【这条路线的历史】" + parts.joined(separator: ";")
    }

    // MARK: 格式化

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MM/dd"; return f.string(from: date)
    }

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
    }

    private static func distanceText(_ meters: Double) -> String {
        meters >= 1_000 ? String(format: "%.1f km", meters / 1_000) : "\(Int(meters)) m"
    }

    private static func paceText(_ secondsPerKm: Double) -> String {
        let m = Int(secondsPerKm) / 60, s = Int(secondsPerKm) % 60
        return "\(m)'\(String(format: "%02d", s))\"/km"
    }

    private static func confidenceText(_ confidence: RouteMatchConfidence) -> String {
        switch confidence {
        case .high: "高置信"
        case .medium: "中置信"
        case .low: "低置信"
        case .none: "无置信"
        }
    }

    private static func trimNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
