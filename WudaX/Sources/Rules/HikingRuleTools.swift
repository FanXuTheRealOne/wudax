import Foundation

enum HikingRuleTools {
    static func analyzeGPX(_ analyzed: AnalyzedGPX) -> AnalyzedGPX { analyzed }

    // MARK: 本次路线 × 过往经历 交叉比对（行前核心）

    /// 用「走过最难的一次」与本次路线交叉比对,得出难度、风险、个性化耗时与分析。
    static func compareToExperience(route: Route, experience: HikerExperience) -> RouteComparison {
        let routeMaxAlt = route.elevationProfile.max() ?? experience.highestAltitudeM
        // 个性化耗时:用户在其最难一次里表现出的相对通用配速的系数,套到本次路线
        let genericHoursForHardest = max(0.5, experience.hardestDistanceKm / 3.5 + experience.hardestAscentM / 600)
        let userFactor = experience.isComplete && genericHoursForHardest > 0
            ? max(0.7, min(1.8, experience.longestDurationH / genericHoursForHardest)) : 1.0
        let genericHoursForRoute = max(0.5, route.distanceKm / 3.5 + route.ascentM / 600)
        let estimatedHours = (genericHoursForRoute * userFactor).rounded(toPlaces: 1)

        let distanceRatio = experience.hardestDistanceKm > 0 ? route.distanceKm / experience.hardestDistanceKm : 1
        let ascentRatio = experience.hardestAscentM > 0 ? route.ascentM / experience.hardestAscentM : 1
        let altitudeRatio = experience.highestAltitudeM > 0 ? routeMaxAlt / experience.highestAltitudeM : 1

        // 超出历史的轴数决定风险
        var exceededAxes = 0
        var analysis: [String] = []
        if ascentRatio > 1.05 {
            exceededAxes += 1
            analysis.append("累计拔高 \(Int(route.ascentM)) m，比你走过最难的一次(\(Int(experience.hardestAscentM)) m)高 \(Int((ascentRatio - 1) * 100))%。")
        }
        if altitudeRatio > 1.03 {
            exceededAxes += 1
            analysis.append("最高海拔约 \(Int(routeMaxAlt)) m，超过你到过的最高点(\(Int(experience.highestAltitudeM)) m)，高原反应与体温风险上升。")
        }
        if distanceRatio > 1.1 {
            exceededAxes += 1
            analysis.append("总距离 \(String(format: "%.1f", route.distanceKm)) km，长于你走过最难的一次(\(String(format: "%.1f", experience.hardestDistanceKm)) km)。")
        }
        if route.descentM >= 1200 {
            analysis.append("后半程连续下降约 \(Int(route.descentM)) m，长下坡对膝盖压力集中。")
        }

        let difficultyLabel: String
        let riskLevel: RiskLevel
        switch exceededAxes {
        case 0: difficultyLabel = "在能力范围内"; riskLevel = route.descentM >= 1200 ? .medium : .low
        case 1: difficultyLabel = "有挑战"; riskLevel = .mediumHigh
        case 2: difficultyLabel = "接近体能极限"; riskLevel = .high
        default: difficultyLabel = "超出体能极限"; riskLevel = .high
        }
        if exceededAxes >= 2 {
            analysis.append("多项指标同时超过你的历史最难,已接近或超出体能极限,但幅度尚可控,因此给出「\(riskLevel.rawValue)」风险,建议充分准备或降级。")
        } else if analysis.isEmpty {
            analysis.append("本次路线各项指标都在你走过的范围内,按常规准备即可。")
        }

        let isOvernight = estimatedHours > 13
        return RouteComparison(difficultyLabel: difficultyLabel, riskLevel: riskLevel,
                               estimatedHours: estimatedHours, isOvernight: isOvernight,
                               analysis: analysis, distanceRatio: distanceRatio,
                               ascentRatio: ascentRatio, altitudeRatio: altitudeRatio)
    }

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
        let hours = route.estimatedHours
        let isOvernight = hours > 13
        // 单日高强度徒步:约 0.4 L/h 需水,含热修正;过夜额外备炊用水
        let heatFactor = max(0, (temperatureCelsius ?? 18) - 18) * 0.012
        let waterRate = 0.4 + heatFactor
        let water = (hours * waterRate + (isOvernight ? 1.5 : 0.5)).rounded(toPlaces: 1)
        let electrolyte = (water / 3).rounded(toPlaces: 1)   // 约 1/3 走电解质
        // 单日高强度:约 260 kcal/h 需随身补充(非全部消耗,按可摄入量)
        let foodRate = isOvernight ? 300.0 : 260.0
        let totalKcal = (hours * foodRate).rounded()
        // 餐数:主升/最高点/长下坡前后各补一次,约每 3 小时一餐
        let meals = max(2, Int((hours / 3).rounded(.up)))
        let explanation = isOvernight
            ? "预计 \(String(format: "%.1f", hours)) 小时、需过夜(重装线):按每餐 ≥\(Int(totalKcal / Double(meals))) kcal 备 \(meals) 餐,含 \(electrolyte) L 电解质;炊具/宿营装备自备。"
            : "预计 \(String(format: "%.1f", hours)) 小时单日高强度:备 \(meals) 餐、每餐 ≥\(Int(totalKcal / Double(meals))) kcal,其中电解质水约 \(electrolyte) L(占总水 1/3)。"
        return SupplyBudgetResult(waterLiters: water, foodKilocalories: totalKcal,
                                  waterRatePerHour: waterRate, feedingRatePerHour: foodRate,
                                  explanation: explanation, mealsCount: meals,
                                  electrolyteLiters: electrolyte, isOvernight: isOvernight)
    }

    static func buildEquipmentChecklist(route: Route, supply: SupplyBudgetResult, qualityScore: Int = 100) -> [EquipmentItem] {
        let headlampHours = supply.isOvernight ? 10 : 8
        var items = [
            EquipmentItem(title: "头灯 + 备用电池", reason: "至少保证可用 \(headlampHours) 小时(约一个夜晚)", required: true),
            EquipmentItem(title: "饮水 ≥ \(String(format: "%.1f", supply.waterLiters)) L", reason: "含电解质约 \(String(format: "%.1f", supply.electrolyteLiters)) L", required: true),
            EquipmentItem(title: "食物 \(supply.mealsCount) 餐 / ≥ \(Int(supply.foodKilocalories)) kcal", reason: "按单日高强度能量需求", required: true),
            EquipmentItem(title: "保暖层 + 雨具", reason: "山脊风口与天气变化的基本余量", required: true),
            EquipmentItem(title: "登山杖", reason: "长下坡降低膝部负荷", required: route.descentM >= 1000 || route.hasUnverifiedSegment),
            EquipmentItem(title: "离线 GPX + 撤退点标记", reason: qualityScore < 70 ? "轨迹质量偏低,增加冗余" : "无网络时保持方向感", required: true)
        ]
        if supply.isOvernight {
            items.append(.init(title: "宿营装备(帐篷/睡袋/炉具)", reason: "预计需过夜,按重装线准备", required: true))
        }
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
            reasons.append("最近心率样本为 \(Int(heartRate)) bpm，先降速并重新确认身体状态")
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
