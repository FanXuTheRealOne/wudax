import Foundation
import SwiftUI

// MARK: - Agent 决策引擎（PRD 触发规则表的 MVP 实现）

enum AgentEngine {

    /// 出发前守门：对照建议下限
    static func gateWarnings(plan: TripPlan) -> [String] {
        var w: [String] = []
        if let water = plan.waterL, water < plan.suggestedWaterL {
            w.append("当前水量 \(fmt(water)) L 低于建议下限 \(fmt(plan.suggestedWaterL)) L")
        }
        if let food = plan.foodKcal, food < plan.suggestedFoodKcal {
            w.append("食物 \(Int(food)) kcal 低于建议 \(Int(plan.suggestedFoodKcal)) kcal")
        }
        if plan.route.hasUnverifiedSegment {
            w.append("路线含无路/探路段，撤退点稀少")
        }
        return w
    }

    /// 行中决策：按余量叠加保守止损
    static func evaluate(status: TripStatus, plan: TripPlan) -> AgentDecision {
        var reasons: [String] = []
        var score = 0

        // 补给余量
        let hoursRemaining = max(plan.route.estimatedHours - status.elapsedHours, 0)
        let waterNeeded = hoursRemaining * 0.35
        if status.remainingWaterL < waterNeeded * 0.6 {
            score += 2; reasons.append("剩余水量不足以支撑到下一安全点")
        } else if status.remainingWaterL < waterNeeded {
            score += 1; reasons.append("剩余水量低于剩余路程预估需求")
        }

        // 膝部状态 × 后续下坡
        if status.kneePain >= 7 {
            score += 3; reasons.append("膝痛 \(Int(status.kneePain))/10，已接近不可继续水平")
        } else if status.kneePain >= 4 && status.upcomingLongDescent {
            score += 2; reasons.append("膝痛 \(Int(status.kneePain))/10，且后续仍有连续长下坡")
        }

        // 困倦
        if status.drowsiness >= 7 {
            score += 2; reasons.append("困倦 \(Int(status.drowsiness))/10，判断力下降风险")
        } else if status.drowsiness >= 5 {
            score += 1; reasons.append("困倦 \(Int(status.drowsiness))/10，注意节奏")
        }

        // 日照余量
        if status.hoursToSunset < 2 && hoursRemaining > status.hoursToSunset {
            score += 2; reasons.append("日落前无法完成剩余路段，将进入夜间下撤")
        } else if status.hoursToSunset < 3 && hoursRemaining > status.hoursToSunset {
            score += 1; reasons.append("距日落 \(fmt(status.hoursToSunset)) 小时，时间余量收紧")
        }

        // 进度
        if status.planDeltaMin <= -40 {
            score += 1; reasons.append("落后计划 \(-status.planDeltaMin) 分钟")
        }

        // 路线可信度
        if plan.route.hasUnverifiedSegment && score >= 2 {
            score += 1; reasons.append("路线可信度低且撤退点稀少")
        }

        let verdict: AgentVerdict =
            score >= 5 ? .retreat :
            score >= 3 ? .downgrade :
            score >= 1 ? .cautious : .proceed

        if reasons.isEmpty { reasons = ["各项余量正常"] }

        return AgentDecision(
            verdict: verdict,
            reasons: reasons,
            watchHint: watchHint(verdict: verdict, reasons: reasons),
            detail: detail(verdict: verdict, status: status, plan: plan)
        )
    }

    private static func watchHint(verdict: AgentVerdict, reasons: [String]) -> String {
        switch verdict {
        case .proceed: return "状态良好，按计划继续。"
        case .cautious: return "谨慎继续。\(reasons.first ?? "")"
        case .downgrade: return "建议降级。低补给 + 长下坡 + 夜间风险叠加。"
        case .retreat: return "建议撤退。多项余量同时下降。"
        }
    }

    private static func detail(verdict: AgentVerdict, status: TripStatus, plan: TripPlan) -> String {
        switch verdict {
        case .proceed:
            return "补给、时间与身体状态余量充足。保持当前节奏，下一次确认在 90 分钟后或长下坡前。"
        case .cautious:
            return "个别指标开始收紧，暂不需要改变计划，但请在下一个关键点重新确认状态。"
        case .downgrade:
            return "如果继续前往终点，回程预计进入夜间下撤。你当前水量偏低，且后续仍有连续下降。建议在当前节点降级或撤退。"
        case .retreat:
            return "补给、日照与膝部状态多项余量同时下降，且即将越过不可逆点。建议立即从当前节点下撤：2.1 km 可到公路，日落前可完成。"
        }
    }

    private static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
