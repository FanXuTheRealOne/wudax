import XCTest
@testable import WudaX

final class HikingRuleToolsTests: XCTestCase {
    func testRouteLoadAndSupplyBudgetAreDeterministic() {
        let route = SampleData.wugongshan
        let load = HikingRuleTools.calculateRouteLoad(route: route)
        let supply = HikingRuleTools.calculateSupplyBudget(route: route, profile: FatigueProfile())

        XCTAssertEqual(load.label, "高负荷")
        XCTAssertGreaterThan(load.score, 5)
        XCTAssertEqual(supply.waterLiters, 3.8, accuracy: 0.01)
        XCTAssertGreaterThan(supply.foodKilocalories, 2_000)
    }

    func testReadinessPenalizesLowSleepAndPain() {
        let readiness = HikingRuleTools.calculateUserReadiness(snapshot: nil,
                                                                subjective: ["sleepHours": 4, "fatigue": 6, "pain": 5])
        XCTAssertLessThan(readiness.score, 50)
        XCTAssertTrue(readiness.reasons.contains { $0.contains("睡眠") })
        XCTAssertTrue(readiness.reasons.contains { $0.contains("疼痛") })
    }

    func testControlledActionNeverInventsActionOutsideWhitelist() {
        var status = TripStatus()
        status.remainingWaterL = 0.2
        status.elapsedHours = 8
        status.kneePain = 8
        status.hoursToSunset = 1
        let decision = HikingRuleTools.evaluateFatigueRisk(status: status, plan: SampleData.plan)
        let action = HikingRuleTools.selectControlledAction(risk: decision, status: status, plan: SampleData.plan)
        XCTAssertEqual(action.action, .turnBack)
        XCTAssertTrue(ControlledAction.allCases.contains(action.action))
    }
}

