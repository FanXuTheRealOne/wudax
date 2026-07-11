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

    @MainActor
    func testRouteRecordLinkRoundTripsAndFiltersByRoute() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let summary = HikingRuleTools.summarizeTrip(plan: SampleData.plan, status: TripStatus())
        let advice = HikingRuleTools.buildTrainingAdvice(profile: FatigueProfile(), challenge: .init(score: 0, label: "在能力范围", reasons: [], distanceGapKm: 0, ascentGapMeters: 0, descentGapKm: 0))
        let routeA = UUID()
        let routeB = UUID()
        let older = StoredTrip(id: UUID(), completedAt: Date(timeIntervalSinceNow: -7200), route: nil,
                               summary: summary, events: [], reviewAnswers: [:], trainingAdvice: advice,
                               routeRecordID: routeA, startedAt: Date(timeIntervalSinceNow: -10_800),
                               endedByRetreat: false)
        let newer = StoredTrip(id: UUID(), completedAt: Date(), route: nil,
                               summary: summary, events: [], reviewAnswers: [:], trainingAdvice: advice,
                               routeRecordID: routeA, startedAt: Date(timeIntervalSinceNow: -3600),
                               endedByRetreat: true)
        let other = StoredTrip(id: UUID(), completedAt: Date(), route: nil,
                               summary: summary, events: [], reviewAnswers: [:], trainingAdvice: advice,
                               routeRecordID: routeB)

        let store = TripStore(directory: directory)
        store.save(older)
        store.save(newer)
        store.save(other)

        let logs = store.trips(forRoute: routeA)
        XCTAssertEqual(logs.map(\.id), [newer.id, older.id])
        XCTAssertEqual(logs.first?.endedByRetreat, true)
        XCTAssertTrue(store.trips(forRoute: UUID()).isEmpty)

        // 重新加载后关联关系仍在(持久化往返)。
        let reloaded = TripStore(directory: directory)
        XCTAssertEqual(reloaded.trips(forRoute: routeA).map(\.id), [newer.id, older.id])
        XCTAssertEqual(reloaded.trips(forRoute: routeA).first?.routeRecordID, routeA)
    }

    @MainActor
    func testDecodesLegacyTripsWithoutRouteLinkFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let summary = HikingRuleTools.summarizeTrip(plan: SampleData.plan, status: TripStatus())
        let advice = HikingRuleTools.buildTrainingAdvice(profile: FatigueProfile(), challenge: .init(score: 0, label: "在能力范围", reasons: [], distanceGapKm: 0, ascentGapMeters: 0, descentGapKm: 0))
        let legacy = StoredTrip(id: UUID(), completedAt: Date(), route: nil, summary: summary,
                                events: [], reviewAnswers: [:], trainingAdvice: advice)
        // 旧版 JSON 里没有 routeRecordID/startedAt/endedByRetreat 键。
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode([legacy])) as! [[String: Any]]
        json[0].removeValue(forKey: "routeRecordID")
        json[0].removeValue(forKey: "startedAt")
        json[0].removeValue(forKey: "endedByRetreat")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: directory.appendingPathComponent("wudax-trips.json"))

        let store = TripStore(directory: directory)
        XCTAssertEqual(store.trips.count, 1)
        XCTAssertNil(store.trips.first?.routeRecordID)
        XCTAssertNil(store.trips.first?.endedByRetreat)
    }
}
