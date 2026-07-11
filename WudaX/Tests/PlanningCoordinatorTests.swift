import XCTest
import Combine
@testable import WudaX

final class PlanningCoordinatorTests: XCTestCase {
    private let completeExperience = HikerExperience(hardestDistanceKm: 20,
                                                     hardestAscentM: 1200,
                                                     highestAltitudeM: 3000,
                                                     longestDurationH: 8)

    @MainActor
    func testStartPlanningFlowImportsGPXBeforeBuildingReport() throws {
        let coordinator = PlanningCoordinator()
        coordinator.experience = completeExperience
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))
        coordinator.importGPX(from: url)

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
    func testRouteImportRemainsAvailableBeforeExperienceIsComplete() throws {
        let coordinator = PlanningCoordinator()
        coordinator.experience = HikerExperience()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))

        coordinator.importGPX(from: url)

        XCTAssertFalse(coordinator.experienceComplete)
        XCTAssertTrue(coordinator.canImportGPX)
    }

    @MainActor
    func testExperienceIsRequiredBeforeBuildingReport() throws {
        let coordinator = PlanningCoordinator()
        coordinator.experience = HikerExperience()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))
        coordinator.importGPX(from: url)

        XCTAssertNil(coordinator.buildPlan(profile: FatigueProfile()))

        coordinator.experience = completeExperience
        let result = try XCTUnwrap(coordinator.buildPlan(profile: FatigueProfile()))
        XCTAssertFalse(result.comparison.difficultyLabel.isEmpty)
        XCTAssertFalse(result.equipment.isEmpty)
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

        session.planning.answerHardestDistance(18)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(session.planning.experience.hardestDistanceKm, 18)
        _ = cancellable
    }
}
