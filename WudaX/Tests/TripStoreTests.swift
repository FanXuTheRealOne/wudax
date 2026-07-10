import XCTest
@testable import WudaX

final class TripStoreTests: XCTestCase {
    @MainActor
    func testStoresTripAndReloadsFromApplicationSupportFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let summary = HikingRuleTools.summarizeTrip(plan: SampleData.plan, status: TripStatus())
        let advice = HikingRuleTools.buildTrainingAdvice(profile: FatigueProfile(), challenge: .init(score: 0, label: "在能力范围", reasons: [], distanceGapKm: 0, ascentGapMeters: 0, descentGapKm: 0))
        let trip = StoredTrip(id: UUID(), completedAt: Date(), route: nil, summary: summary, events: [], reviewAnswers: [:], trainingAdvice: advice)
        let store = TripStore(directory: directory)
        store.save(trip)
        XCTAssertEqual(store.trips.first, trip)
        let reloaded = TripStore(directory: directory)
        XCTAssertEqual(reloaded.trips.first, trip)
    }
}
