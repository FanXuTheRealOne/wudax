import XCTest
@testable import WudaX

final class AgentToolOrchestratorTests: XCTestCase {
    func testToolCatalogContainsDeterministicRiskTools() {
        let names = AgentToolOrchestrator.toolSpecifications.compactMap { spec in
            (spec["function"] as? [String: Any])?["name"] as? String
        }
        XCTAssertTrue(names.contains("calculate_route_load"))
        XCTAssertTrue(names.contains("evaluate_fatigue_risk"))
        XCTAssertTrue(names.contains("select_controlled_action"))
    }

    func testUnknownToolIsRejected() {
        let output = AgentToolOrchestrator.execute(.init(name: "delete_trip", arguments: [:]), plan: SampleData.plan, status: TripStatus())
        XCTAssertTrue(output.contains("白名单"))
    }
}
