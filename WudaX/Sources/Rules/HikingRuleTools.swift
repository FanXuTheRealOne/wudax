import Foundation

enum HikingRuleTools {
    static func analyzeGPX(_ analyzed: AnalyzedGPX) -> AnalyzedGPX { analyzed }

    static func calculateRouteLoad(route: Route) -> RouteLoadResult {
        let distance = route.distanceKm
        let ascent = route.ascentM
        let descent = route.descentM
        var score = 0
        var reasons: [String] = []

        if distance >= 20 { score += 2; reasons.append("距离超过 20 km") }
        else if distance >= 12 { score += 1; reasons.append("距离超过 12 km") }
        if ascent >= 1500 { score += 2; reasons.append("累计爬升超过 1500 m") }
        else if ascent >= 800 { score += 1; reasons.append("累计爬升超过 800 m") }
        if descent >= 1200 { score += 2; reasons.append("后程累计下降较大") }
        if route.hasUnverifiedSegment { score += 2; reasons.append("包含未验证路段") }
        if route.isOutAndBack { score += 1; reasons.append("原路返回会放大回程时间风险") }

        let label = score >= 6 ? "高负荷" : score >= 3 ? "中高负荷" : score >= 1 ? "中负荷" : "低负荷"
        return RouteLoadResult(score: score, label: label, reasons: reasons.isEmpty ? ["路线负荷在常规范围"] : reasons,
                               distanceKm: distance, ascentMeters: ascent, descentMeters: descent,
                               estimatedHours: route.estimatedHours)
    }

    static func calculateUserReadiness(snapshot: HealthSnapshot?,
                                       subjective: [String: Double],
                                       personalHealth: PersonalHealthProfile? = nil) -> ReadinessResult {
        var score = 70
        var reasons: [String] = []
        var missing: [String] = []

        if let sleep = subjective["sleepHours"] ?? snapshot?.reading(.sleepDuration)?.value {
            if sleep < 5 { score -= 25; reasons.append("最近睡眠少于 5 小时") }
            else if sleep < 6.5 { score -= 12; reasons.append("睡眠余量偏低") }
            else { score += 5 }
        } else { missing.append("睡眠") }

        if let fatigue = subjective["fatigue"] {
            score -= Int(fatigue.rounded()) * 2
            if fatigue >= 7 { reasons.append("主观疲劳较高") }
        } else { missing.append("主观疲劳") }

        if let pain = subjective["pain"] {
            score -= Int(pain.rounded()) * 2
            if pain >= 5 { reasons.append("存在明显疼痛") }
        } else { missing.append("疼痛") }

        if let restingHeartRate = snapshot?.reading(.restingHeartRate)?.value,
           let baseline = subjective["baselineRestingHeartRate"],
           restingHeartRate - baseline >= 8 {
            score -= 12
            reasons.append("静息心率高于个人基线")
        }

        if let personalHealth, personalHealth.isComplete {
            score -= personalHealth.readinessPenalty
            reasons.append(contentsOf: personalHealth.cautionReasons)
        }

        score = min(max(score, 0), 100)
        let label = score >= 80 ? "准备充分" : score >= 60 ? "基本可行" : score >= 40 ? "需要谨慎" : "不建议按原计划"
        return ReadinessResult(score: score, label: label,
                               reasons: reasons.isEmpty ? ["暂无明显准备度红旗"] : reasons,
                               missingInputs: missing)
    }

    static func calculateChallengeGap(route: Route, profile: FatigueProfile, readiness: ReadinessResult) -> ChallengeGapResult {
        let descentGap = max(route.descentM / 1000 - profile.descentToleranceKm, 0)
        let distanceGap = max(route.distanceKm - 18, 0)
        let ascentGap = max(route.ascentM - 1200, 0)
        var score = 0
        var reasons: [String] = []
        if descentGap > 0 { score += 2; reasons.append("累计下降超出当前下坡耐受 \(String(format: "%.1f", descentGap)) km") }
        if distanceGap > 3 { score += 1; reasons.append("距离超出常规训练长度") }
        if ascentGap > 400 { score += 1; reasons.append("爬升超出近期常规水平") }
        if readiness.score < 50 { score += 2; reasons.append("当天准备度降低挑战余量") }
        let label = score >= 5 ? "明显超出" : score >= 3 ? "有挑战" : "在能力范围"
        return ChallengeGapResult(score: score, label: label, reasons: reasons.isEmpty ? ["路线与当前能力匹配"] : reasons,
                                  distanceGapKm: distanceGap, ascentGapMeters: ascentGap, descentGapKm: descentGap)
    }

    static func calculateSupplyBudget(route: Route, profile: FatigueProfile, temperatureCelsius: Double? = nil) -> SupplyBudgetResult {
        let heatFactor = max(0, (temperatureCelsius ?? 18) - 18) * 0.012
        let waterRate = max(0.25, profile.waterRatePerHour + heatFactor)
        let water = (route.estimatedHours * waterRate + 0.5).rounded(toPlaces: 1)
        let foodRate = route.estimatedHours >= 8 ? 220.0 : 180.0
        return SupplyBudgetResult(waterLiters: water, foodKilocalories: (route.estimatedHours * foodRate).rounded(),
                                  waterRatePerHour: waterRate, feedingRatePerHour: foodRate,
                                  explanation: "按预计 \(String(format: "%.1f", route.estimatedHours)) 小时、个人耗水速率和 0.5 L 安全余量估算")
    }

    static func buildEquipmentChecklist(route: Route, supply: SupplyBudgetResult, qualityScore: Int = 100) -> [EquipmentItem] {
        var items = [
            EquipmentItem(title: "头灯与备用电源", reason: "预计行程较长或可能接近日落", required: route.estimatedHours >= 6),
            EquipmentItem(title: "保暖层与雨具", reason: "山脊风口和天气变化的基本余量", required: true),
            EquipmentItem(title: "饮水与电解质", reason: "至少准备 \(String(format: "%.1f", supply.waterLiters)) L 水预算", required: true),
            EquipmentItem(title: "基础急救与个人药品", reason: "离线行程的最低安全配置", required: true),
            EquipmentItem(title: "离线 GPX 与纸面撤退点", reason: qualityScore < 70 ? "路线数据质量较低，增加冗余" : "无网络时保持方向感", required: true)
        ]
        if route.hasUnverifiedSegment { items.append(.init(title: "登山杖", reason: "未验证路段和长下坡降低膝部负荷", required: true)) }
        return items
    }

    static func matchRouteProgress(document: GPXDocument, latitude: Double, longitude: Double) -> RouteProgress? {
        guard let route = try? GPXRoutePreprocessor().prepare(document) else { return nil }
        let result = GPXRouteMatcher(route: route).match(RouteLocationInput(
            coordinate: RouteCoordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracyMeters: 10,
            timestamp: Date(),
            speedMetersPerSecond: nil,
            courseDegrees: nil,
            altitudeMeters: nil,
            cadenceStepsPerMinute: nil
        ))
        let nearestVertexIndex = route.vertices.indices.min {
            abs(route.vertices[$0].cumulativeDistanceMeters - result.routeProgressMeters) <
            abs(route.vertices[$1].cumulativeDistanceMeters - result.routeProgressMeters)
        } ?? 0
        return RouteProgress(
            nearestPointIndex: route.vertices[nearestVertexIndex].sourcePointIndex,
            distanceAlongRouteMeters: result.routeProgressMeters,
            distanceToRouteMeters: result.distanceToRouteMeters,
            fractionComplete: result.routeProgressMeters / max(route.totalDistanceMeters, 1),
            estimatedElevationMeters: route.vertices[nearestVertexIndex].elevationMeters
        )
    }

    static func evaluateFatigueRisk(status: TripStatus, plan: TripPlan, snapshot: HealthSnapshot? = nil) -> RiskEvaluation {
        let decision = AgentEngine.evaluate(status: status, plan: plan)
        let stale = snapshot?.readings.values.contains { $0.freshness == .stale } ?? false
        let confidence = stale ? 0.62 : snapshot == nil ? 0.75 : 0.9
        var level: RiskLevel = decision.verdict == .retreat ? .high : decision.verdict == .downgrade ? .mediumHigh : decision.verdict == .cautious ? .medium : .low
        var reasons = decision.reasons
        if let heartRate = snapshot?.reading(.heartRate)?.value, heartRate >= 150 {
            reasons.append("最近心率样本为 (Int(heartRate)) bpm，先降速并重新确认身体状态")
            if level == .low { level = .medium }
        }
        if stale { reasons.append("部分身体数据已过期，当前结论可信度降低") }
        return RiskEvaluation(level: level, reasons: reasons, confidence: confidence, staleData: stale)
    }

    static func selectControlledAction(risk: RiskEvaluation, status: TripStatus, plan: TripPlan) -> ActionRecommendation {
        if risk.level == .high { return .init(action: .turnBack, title: "建议从当前节点折返", detail: "多个余量同时收紧，先回到已知安全点。", urgency: .high) }
        if risk.reasons.contains(where: { $0.contains("水") }) { return .init(action: .hydrate, title: "先补水再决定", detail: "补水后休息 10 分钟，重新确认膝痛与时间。", urgency: risk.level) }
        if status.upcomingLongDescent && status.kneePain >= 4 { return .init(action: .slowDown, title: "长下坡前降速", detail: "缩短步幅，必要时在下坡起点降级。", urgency: .mediumHigh) }
        if risk.level == .mediumHigh { return .init(action: .shortenRoute, title: "建议缩短路线", detail: "保留安全余量，不把复杂地形留到日落后。", urgency: .mediumHigh) }
        if risk.level == .medium { return .init(action: .rest, title: "休息后谨慎继续", detail: "休息并重新确认身体和补给状态。", urgency: .medium) }
        return .init(action: .continueRoute, title: "按计划继续", detail: "当前数据没有触发升级行动。", urgency: .low)
    }

    static func summarizeTrip(plan: TripPlan, status: TripStatus, peakRisk: RiskLevel = .low, keyEvents: [String] = []) -> TripSummary {
        TripSummary(plannedDistanceKm: plan.route.distanceKm, actualDistanceKm: status.elapsedKm,
                    plannedHours: plan.route.estimatedHours, actualHours: status.elapsedHours,
                    planDeltaMinutes: status.planDeltaMin, peakRisk: peakRisk, keyEvents: keyEvents)
    }

    static func updatePersonalBaseline(profile: inout FatigueProfile, status: TripStatus, reviewAnswers: [String: String]) {
        if let knee = reviewAnswers["膝痛"], knee != "没有膝痛" { profile.descentToleranceKm = max(3, profile.descentToleranceKm - 0.5) }
        if status.elapsedHours > 0, status.remainingWaterL < 0.5 { profile.waterRatePerHour = min(0.8, profile.waterRatePerHour + 0.03) }
        profile.tripsRecorded += 1
    }

    static func buildTrainingAdvice(profile: FatigueProfile, challenge: ChallengeGapResult) -> TrainingAdvice {
        if challenge.score >= 4 {
            return TrainingAdvice(headline: "下一次先补能力差距，再挑战同等级路线",
                                  sessions: ["每周 1 次 60–90 分钟爬坡", "每周 1 次受控下坡与登山杖练习", "连续两天保持低强度有氧"],
                                  nextRouteAdjustment: "下次路线先把累计下降控制在 \(String(format: "%.1f", profile.descentToleranceKm)) km 内")
        }
        return TrainingAdvice(headline: "维持当前训练节奏，逐步增加下坡耐受",
                              sessions: ["每周 1 次坡度行走", "每周 1 次轻松长距离", "继续记录睡眠、补水和膝痛"],
                              nextRouteAdjustment: "保持当前长度，单次只增加一个难度变量")
    }

}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        var scale = 1.0
        for _ in 0..<places { scale *= 10 }
        return (self * scale).rounded() / scale
    }
}
