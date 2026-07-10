import XCTest
import CoreLocation
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
        let planPoints = plan.segments.flatMap(\.points)
        XCTAssertTrue(planPoints.allSatisfy { $0.time == nil && $0.speedMetersPerSecond == nil })
        XCTAssertTrue(planPoints.allSatisfy { $0.heartRateBPM == nil && $0.cadenceRPM == nil })
    }

    func testParsesRoutePointsAndVendorTrackpointMetrics() throws {
        let document = try GPXParser().parse(data: data("""
        <?xml version="1.0"?>
        <gpx version="1.1" creator="vendor" xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <rte>
            <name>计划路线</name>
            <rtept lat="27.0000" lon="114.0000"><ele>100</ele></rtept>
            <rtept lat="27.0010" lon="114.0000"><ele>110</ele></rtept>
          </rte>
          <trk>
            <trkpt lat="27.0010" lon="114.0000">
              <time>2026-06-28T08:00:00+08:00</time>
              <extensions>
                <gpxtpx:TrackPointExtension>
                  <gpxtpx:speed>2.5</gpxtpx:speed>
                  <gpxtpx:hr>142</gpxtpx:hr>
                  <gpxtpx:cad>82</gpxtpx:cad>
                </gpxtpx:TrackPointExtension>
              </extensions>
            </trkpt>
          </trk>
        </gpx>
        """))

        XCTAssertEqual(document.name, "计划路线")
        XCTAssertEqual(document.segments.count, 2)
        XCTAssertEqual(document.segments[0].points.count, 2)
        XCTAssertEqual(document.segments[1].points.first?.speedMetersPerSecond, 2.5)
        XCTAssertEqual(document.segments[1].points.first?.heartRateBPM, 142)
        XCTAssertEqual(document.segments[1].points.first?.cadenceRPM, 82)
        XCTAssertNotNil(document.segments[1].points.first?.time)
    }

    func testAcceptsTrackPointsWithoutExplicitTrackSegment() throws {
        let document = try GPXParser().parse(data: data("""
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkpt lat="27.0000" lon="114.0000" />
            <trkpt lat="27.0005" lon="114.0000" />
          </trk>
        </gpx>
        """))

        XCTAssertEqual(document.segments.count, 1)
        XCTAssertEqual(document.points.count, 2)
    }

    func testReportsInvalidCoordinatesInsteadOfAddingThemToTheTrack() throws {
        let document = try GPXParser().parse(data: data("""
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="91" lon="114"><ele>100</ele></trkpt>
            <trkpt lat="27.0000" lon="114.0000"><ele>100</ele></trkpt>
          </trkseg></trk>
        </gpx>
        """))

        XCTAssertEqual(document.points.count, 1)
        XCTAssertEqual(document.ignoredPointCount, 1)
        let analyzed = GPXAnalyzer().analyze(document)
        XCTAssertTrue(analyzed.qualityIssues.contains(where: { issue in issue.kind == .invalidCoordinate }))
    }

    func testElevationNoiseDeadbandPreventsFalseClimbAndDescent() throws {
        let document = try GPXParser().parse(data: data("""
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="27.0000" lon="114.0000"><ele>100</ele></trkpt>
            <trkpt lat="27.0001" lon="114.0000"><ele>101</ele></trkpt>
            <trkpt lat="27.0002" lon="114.0000"><ele>100</ele></trkpt>
            <trkpt lat="27.0003" lon="114.0000"><ele>105</ele></trkpt>
            <trkpt lat="27.0004" lon="114.0000"><ele>104</ele></trkpt>
          </trkseg></trk>
        </gpx>
        """))

        let analyzed = GPXAnalyzer().analyze(document)
        XCTAssertEqual(analyzed.statistics.ascentMeters, 5, accuracy: 0.01)
        XCTAssertEqual(analyzed.statistics.descentMeters, 0, accuracy: 0.01)
    }

    func testDecodesLegacyDocumentWithoutParserDiagnostics() throws {
        let legacy = Data("""
        {
          "name": "旧路线",
          "creator": null,
          "segments": [{"points": [{"latitude": 27, "longitude": 114, "elevationMeters": null, "time": null, "speedMetersPerSecond": null}]}],
          "waypoints": [],
          "purpose": "plannedRoute"
        }
        """.utf8)

        let document = try JSONDecoder().decode(GPXDocument.self, from: legacy)
        XCTAssertEqual(document.ignoredPointCount, 0)
        XCTAssertEqual(document.ignoredWaypointCount, 0)
    }

    func testBackgroundLocationUpdatesRequireAlwaysAuthorizationAndCapability() {
        XCTAssertFalse(LocationService.shouldEnableBackgroundLocationUpdates(
            authorizationStatus: .authorizedAlways,
            hasBackgroundLocationMode: false
        ))
        XCTAssertTrue(LocationService.shouldEnableBackgroundLocationUpdates(
            authorizationStatus: .authorizedAlways,
            hasBackgroundLocationMode: true
        ))
        XCTAssertFalse(LocationService.shouldEnableBackgroundLocationUpdates(
            authorizationStatus: .authorizedWhenInUse,
            hasBackgroundLocationMode: true
        ))
    }

    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sanitized-route", withExtension: "gpx"))
        return try Data(contentsOf: url)
    }

    private func data(_ string: String) -> Data { Data(string.utf8) }
}
