import Foundation

struct AgentToolCall: Codable, Equatable, Sendable {
    var name: String
    var arguments: [String: Double]
}

enum AgentToolOrchestrator {
    static let toolSpecifications: [[String: Any]] = [
        spec("analyze_gpx", "解析 GPX 的距离、海拔和数据质量", ["route_id": ["type": "string"]]),
        spec("calculate_route_load", "计算路线负荷", ["distance_km": ["type": "number"], "ascent_m": ["type": "number"], "descent_m": ["type": "number"]]),
        spec("calculate_user_readiness", "计算当天身体准备度", ["sleep_hours": ["type": "number"], "fatigue": ["type": "number"], "pain": ["type": "number"]]),
        spec("calculate_challenge_gap", "计算路线与个人能力差距", ["descent_tolerance_km": ["type": "number"]]),
        spec("calculate_supply_budget", "计算水和食物预算", ["hours": ["type": "number"]]),
        spec("build_equipment_checklist", "生成装备清单", ["hours": ["type": "number"]]),
        spec("match_route_progress", "把当前位置匹配到 GPX 路线", ["latitude": ["type": "number"], "longitude": ["type": "number"]]),
        spec("evaluate_fatigue_risk", "按确定性规则评估疲劳风险", ["remaining_water_l": ["type": "number"], "knee_pain": ["type": "number"], "drowsiness": ["type": "number"]]),
        spec("select_controlled_action", "从受控行动白名单中选择行动", ["risk": ["type": "string"]]),
        spec("summarize_trip", "生成计划与实际对比", ["actual_km": ["type": "number"], "actual_hours": ["type": "number"]]),
        spec("update_personal_baseline", "根据复盘更新个人基线", ["knee_pain": ["type": "number"]]),
        spec("build_training_advice", "生成下一周期训练建议", ["challenge_score": ["type": "number"]])
    ]

    static func execute(_ call: AgentToolCall, plan: TripPlan, status: TripStatus) -> String {
        guard let name = ToolName(rawValue: call.name) else { return "工具不可用：只允许 WUDAX 白名单工具。" }
        switch name {
        case .routeLoad:
            return encode(HikingRuleTools.calculateRouteLoad(route: plan.route))
        case .supply:
            return encode(HikingRuleTools.calculateSupplyBudget(route: plan.route, profile: FatigueProfile()))
        case .equipment:
            let budget = HikingRuleTools.calculateSupplyBudget(route: plan.route, profile: FatigueProfile())
            return encode(HikingRuleTools.buildEquipmentChecklist(route: plan.route, supply: budget, qualityScore: plan.route.qualityScore))
        case .risk:
            return encode(HikingRuleTools.evaluateFatigueRisk(status: status, plan: plan))
        case .action:
            let risk = HikingRuleTools.evaluateFatigueRisk(status: status, plan: plan)
            return encode(HikingRuleTools.selectControlledAction(risk: risk, status: status, plan: plan))
        case .summary:
            var copy = status
            copy.elapsedKm = call.arguments["actual_km"] ?? status.elapsedKm
            copy.elapsedHours = call.arguments["actual_hours"] ?? status.elapsedHours
            return encode(HikingRuleTools.summarizeTrip(plan: plan, status: copy))
        case .readiness:
            let input: [String: Double] = ["sleepHours": call.arguments["sleep_hours"] ?? 0,
                                            "fatigue": call.arguments["fatigue"] ?? 0,
                                            "pain": call.arguments["pain"] ?? 0]
            return encode(HikingRuleTools.calculateUserReadiness(snapshot: nil, subjective: input))
        default:
            return "工具已注册；需要完整的路线或身体快照后才能执行。"
        }
    }

    static func extractToolCall(from text: String) -> AgentToolCall? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let candidate = String(text[start...end])
        return try? JSONDecoder().decode(AgentToolCall.self, from: Data(candidate.utf8))
    }

    private enum ToolName: String {
        case routeLoad = "calculate_route_load"
        case supply = "calculate_supply_budget"
        case equipment = "build_equipment_checklist"
        case risk = "evaluate_fatigue_risk"
        case action = "select_controlled_action"
        case summary = "summarize_trip"
        case readiness = "calculate_user_readiness"
        case other
    }

    private static func spec(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        ["type": "function", "function": [
            "name": name,
            "description": description,
            "parameters": ["type": "object", "properties": properties, "required": Array(properties.keys)]
        ]]
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
