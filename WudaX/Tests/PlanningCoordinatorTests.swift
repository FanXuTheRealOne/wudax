import XCTest
import Combine
@testable import WudaX

final class PlanningCoordinatorTests: XCTestCase {
    @MainActor
    func testStartPlanningFlowImportsGPXBeforeBuildingReport() throws {
        let coordinator = PlanningCoordinator()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))
        coordinator.importGPX(from: url)
        coordinator.answerInjury(.none)
        coordinator.answerSurgery(.none)
        coordinator.answerMedicalConsideration(.none)
        coordinator.answerSleep(7)
        coordinator.answerFatigue(2)
        coordinator.answerPain(0)

        XCTAssertNotNil(coordinator.analyzedGPX)
        let result = try XCTUnwrap(coordinator.buildPlan(profile: FatigueProfile()))
        XCTAssertEqual(result.route.name, "脱敏测试环线")
        XCTAssertEqual(coordinator.stage, .ready)
    }

    @MainActor
    func testSuccessfulImportClearsPreviousImportError() throws {
        let coordinator = PlanningCoordinator()
        let invalidURL = FileManager.default.temporaryDirectory.appendingPathComponent("broken-route.gpx")
        try Data("not a gpx document".utf8).write(to: invalidURL)
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        coordinator.importGPX(from: invalidURL)
        XCTAssertNotNil(coordinator.importError)

        let validURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))
        coordinator.importGPX(from: validURL)

        XCTAssertNil(coordinator.importError)
        XCTAssertNotNil(coordinator.analyzedGPX)
    }

    @MainActor
    func testPersonalHealthHistoryIsRequiredBeforeBuildingReport() throws {
        let coordinator = PlanningCoordinator()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))
        coordinator.importGPX(from: url)
        coordinator.answerSleep(7)
        coordinator.answerFatigue(2)
        coordinator.answerPain(0)

        XCTAssertFalse(coordinator.personalHealth.isComplete)
        XCTAssertNil(coordinator.buildPlan(profile: FatigueProfile()))

        coordinator.answerInjury(.knee)
        coordinator.answerSurgery(.recovering)
        coordinator.answerSurgeryLocation(.knee)
        coordinator.answerMedicalConsideration(.medication)

        XCTAssertTrue(coordinator.personalHealth.isComplete)
        let result = try XCTUnwrap(coordinator.buildPlan(profile: FatigueProfile()))
        XCTAssertTrue(result.readiness.reasons.contains { $0.contains("膝") || $0.contains("手术") })
    }

    @MainActor
    func testTripSessionForwardsPlanningChangesToSwiftUI() {
        let session = TripSession()
        let expectation = expectation(description: "planning change forwarded")
        var didFulfill = false
        let cancellable = session.objectWillChange.sink { _ in
            guard !didFulfill else { return }
            didFulfill = true
            expectation.fulfill()
        }

        session.planning.answerInjury(.knee)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(session.planning.personalHealth.injury, .knee)
        _ = cancellable
    }
}
