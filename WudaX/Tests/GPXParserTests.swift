import XCTest
@testable import WudaX

final class GPXParserTests: XCTestCase {
    func testParsesNamespacedTrackAndWaypoint() throws {
        let document = try GPXParser().parse(data: fixtureData())

        XCTAssertEqual(document.name, "脱敏测试环线")
        XCTAssertEqual(document.segments.count, 1)
        XCTAssertEqual(document.segments[0].points.count, 5)
        XCTAssertEqual(document.waypoints.first?.name, "安全点")
        XCTAssertEqual(document.segments[0].points[0].speedMetersPerSecond, 1.1)
    }

    func testDerivesRouteStatisticsIndependentlyFromVendorData() throws {
        let document = try GPXParser().parse(data: fixtureData())
        let analyzed = GPXAnalyzer().analyze(document)

        XCTAssertGreaterThan(analyzed.statistics.distanceMeters, 300)
        XCTAssertLessThan(analyzed.statistics.distanceMeters, 500)
        XCTAssertEqual(analyzed.statistics.ascentMeters, 50, accuracy: 0.01)
        XCTAssertEqual(analyzed.statistics.descentMeters, 50, accuracy: 0.01)
        XCTAssertEqual(analyzed.statistics.minimumElevationMeters, 100)
        XCTAssertEqual(analyzed.statistics.maximumElevationMeters, 150)
    }

    func testFlagsTimeRegressionLongGapAndRepeatedPoint() throws {
        let analyzed = GPXAnalyzer().analyze(try GPXParser().parse(data: fixtureData()))
        let issueKinds = Set(analyzed.qualityIssues.map(\.kind))

        XCTAssertTrue(issueKinds.contains(.timeRegression))
        XCTAssertTrue(issueKinds.contains(.longTimeGap))
        XCTAssertTrue(issueKinds.contains(.repeatedCoordinate))
    }

    func testHistoryCopyAsPlanStripsRecordedFields() throws {
        let history = try GPXParser().parse(data: fixtureData())
        let plan = history.copyForPlanning()

        XCTAssertEqual(plan.purpose, .plannedRoute)
        XCTAssertTrue(plan.segments.flatMap(\.points).allSatisfy { $0.time == nil && $0.speedMetersPerSecond == nil })
    }

    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))
        return try Data(contentsOf: url)
    }
}
