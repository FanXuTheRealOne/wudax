import XCTest
@testable import WudaX

final class RouteMatchingTests: XCTestCase {
    func testPreprocessorBuildsCumulativeDistanceAndRemainingAscent() throws {
        let document = makeDocument([
            (27.0000, 114.0000, 100),
            (27.0009, 114.0000, 110),
            (27.0018, 114.0000, 105),
            (27.0027, 114.0000, 120)
        ])

        let route = try GPXRoutePreprocessor().prepare(document)

        XCTAssertEqual(route.vertices.first?.cumulativeDistanceMeters, 0)
        XCTAssertEqual(route.vertices.last?.cumulativeDistanceMeters, route.totalDistanceMeters)
        XCTAssertGreaterThan(route.totalDistanceMeters, 250)
        XCTAssertLessThan(route.totalDistanceMeters, 350)
        XCTAssertEqual(route.totalAscentMeters, 25, accuracy: 0.5)
        XCTAssertEqual(route.vertices.first?.remainingAscentMeters ?? -1, 25, accuracy: 0.5)
        XCTAssertEqual(route.vertices.last?.remainingDistanceMeters ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(route.segments.first?.remainingDistanceAtStartMeters ?? -1,
                       route.totalDistanceMeters, accuracy: 0.01)
        XCTAssertEqual(route.segments.first?.remainingAscentAtStartMeters ?? -1,
                       route.totalAscentMeters, accuracy: 0.01)
    }

    func testPreprocessorDeduplicatesWithoutMutatingSourceDocument() throws {
        let document = makeDocument([
            (27.0000, 114.0000, 100),
            (27.0000, 114.0000, 100),
            (27.0010, 114.0000, 105),
            (27.0020, 114.0010, 110)
        ])

        let route = try GPXRoutePreprocessor().prepare(document)

        XCTAssertEqual(document.points.count, 4)
        XCTAssertEqual(route.sourcePointCount, 4)
        XCTAssertEqual(route.vertices.count, 3)
        XCTAssertEqual(route.segments.count, 2)
    }

    func testPreprocessorProjectsWaypointsAndFindsTurnsAndLoop() throws {
        var document = makeDocument([
            (27.0000, 114.0000, 100),
            (27.0010, 114.0000, 105),
            (27.0010, 114.0010, 110),
            (27.0000, 114.0010, 105),
            (27.0000, 114.0000, 100)
        ])
        document.waypoints = [
            GPXWaypoint(latitude: 27.0010, longitude: 114.0010, elevationMeters: 110, name: "山口")
        ]

        let route = try GPXRoutePreprocessor().prepare(document)

        XCTAssertTrue(route.flags.isLoop)
        XCTAssertFalse(route.turnVertexIndices.isEmpty)
        XCTAssertEqual(route.waypoints.first?.name, "山口")
        XCTAssertGreaterThan(route.waypoints.first?.routeProgressMeters ?? 0, 100)
        XCTAssertLessThan(route.waypoints.first?.distanceFromRouteMeters ?? 100, 2)
    }

    func testPreprocessorRecognizesOutAndBackAndNearbyParallelSegments() throws {
        let document = makeDocument([
            (27.0000, 114.0000, 100),
            (27.0020, 114.0000, 120),
            (27.0020, 114.0001, 120),
            (27.0000, 114.0001, 100)
        ])

        let route = try GPXRoutePreprocessor().prepare(document)

        XCTAssertTrue(route.flags.isOutAndBack)
        XCTAssertFalse(route.ambiguousSegmentPairs.isEmpty)
    }

    func testMatcherProjectsOntoSegmentInsteadOfSnappingToNearestVertex() throws {
        let route = try GPXRoutePreprocessor().prepare(makeDocument([
            (27.0000, 114.0000, 100),
            (27.0000, 114.0100, 100)
        ]))
        let matcher = GPXRouteMatcher(route: route)

        let result = matcher.match(input(latitude: 27.0001, longitude: 114.0050,
                                         accuracy: 5, speed: 1.2, course: 90))

        XCTAssertEqual(result.routeProgressMeters, route.totalDistanceMeters / 2, accuracy: 15)
        XCTAssertEqual(result.matchedCoordinate.latitude, 27.0000, accuracy: 0.00002)
        XCTAssertGreaterThan(result.distanceToRouteMeters, 8)
        XCTAssertLessThan(result.distanceToRouteMeters, 15)
        XCTAssertEqual(result.locationSource, .gpsMatched)
    }

    func testMatcherUsesHeadingToResolveNearbyOppositeSegments() throws {
        let route = try GPXRoutePreprocessor().prepare(makeDocument([
            (27.0000, 114.0000, 100),
            (27.0020, 114.0000, 120),
            (27.0020, 114.0001, 120),
            (27.0000, 114.0001, 100)
        ]))

        let outbound = GPXRouteMatcher(route: route).match(
            input(latitude: 27.0010, longitude: 114.00005,
                  accuracy: 5, speed: 1.3, course: 0)
        )
        let inbound = GPXRouteMatcher(route: route).match(
            input(latitude: 27.0010, longitude: 114.00005,
                  accuracy: 5, speed: 1.3, course: 180)
        )

        XCTAssertLessThan(outbound.routeProgressMeters, route.totalDistanceMeters / 2)
        XCTAssertGreaterThan(inbound.routeProgressMeters, route.totalDistanceMeters / 2)
    }

    func testMatcherRejectsImpossibleProgressTeleportOnOverlappingReturn() throws {
        let route = try GPXRoutePreprocessor().prepare(makeDocument([
            (27.0000, 114.0000, 100),
            (27.0030, 114.0000, 130),
            (27.0000, 114.0000, 100)
        ]))
        let matcher = GPXRouteMatcher(route: route)
        let start = Date(timeIntervalSince1970: 1_000)

        let first = matcher.match(input(latitude: 27.0005, longitude: 114,
                                        accuracy: 5, time: start, speed: 1, course: 0))
        let second = matcher.match(input(latitude: 27.0005, longitude: 114,
                                         accuracy: 5, time: start.addingTimeInterval(5),
                                         speed: 1, course: 180))

        XCTAssertLessThan(first.routeProgressMeters, 100)
        XCTAssertLessThan(second.routeProgressMeters, 120)
        XCTAssertLessThan(abs(second.routeProgressMeters - first.routeProgressMeters), 70)
    }

    func testOffRouteRequiresRepeatedEvidenceAndRespectsPoorAccuracy() throws {
        let route = try GPXRoutePreprocessor().prepare(makeDocument([
            (27.0000, 114.0000, 100),
            (27.0100, 114.0000, 200)
        ]))
        let matcher = GPXRouteMatcher(route: route)
        let start = Date(timeIntervalSince1970: 2_000)

        let first = matcher.match(input(latitude: 27.0040, longitude: 114.0010,
                                        accuracy: 5, time: start, speed: 1, course: 90))
        let second = matcher.match(input(latitude: 27.0041, longitude: 114.0010,
                                         accuracy: 5, time: start.addingTimeInterval(10), speed: 1, course: 90))
        let third = matcher.match(input(latitude: 27.0042, longitude: 114.0010,
                                        accuracy: 5, time: start.addingTimeInterval(20), speed: 1, course: 90))

        XCTAssertFalse(first.isOffRoute)
        XCTAssertFalse(second.isOffRoute)
        XCTAssertTrue(third.isOffRoute)
        XCTAssertGreaterThan(third.distanceToRouteMeters, 90)
        XCTAssertNotEqual(third.offRouteConfidence, .none)

        let poorAccuracy = GPXRouteMatcher(route: route).match(
            input(latitude: 27.0040, longitude: 114.0010,
                  accuracy: 100, time: start, speed: 1, course: 90)
        )
        XCTAssertFalse(poorAccuracy.isOffRoute)
        XCTAssertNotEqual(poorAccuracy.confidence, .high)
    }

    func testMatcherReturnsRemainingAscentAndNextWaypoint() throws {
        var document = makeDocument([
            (27.0000, 114.0000, 100),
            (27.0010, 114.0000, 200),
            (27.0020, 114.0000, 150)
        ])
        document.waypoints = [
            GPXWaypoint(latitude: 27.0010, longitude: 114.0000, elevationMeters: 200, name: "垭口")
        ]
        let route = try GPXRoutePreprocessor().prepare(document)

        let result = GPXRouteMatcher(route: route).match(
            input(latitude: 27.0001, longitude: 114.0000,
                  accuracy: 5, speed: 1, course: 0)
        )

        XCTAssertGreaterThan(result.remainingAscentMeters, 85)
        XCTAssertLessThan(result.remainingAscentMeters, 95)
        XCTAssertEqual(result.nextWaypoint?.name, "垭口")
        XCTAssertGreaterThan(result.distanceToNextWaypointMeters ?? 0, 80)
    }

    func testShortGPSLossIsEstimatedAndLongLossFallsBackToLastKnown() throws {
        let route = try GPXRoutePreprocessor().prepare(makeDocument([
            (27.0000, 114.0000, 100),
            (27.0100, 114.0000, 200)
        ]))
        let matcher = GPXRouteMatcher(route: route)
        let start = Date(timeIntervalSince1970: 3_000)
        let reliable = matcher.match(input(latitude: 27.0010, longitude: 114,
                                           accuracy: 5, time: start, speed: 1.2, course: 0))

        let estimated = matcher.locationUnavailable(at: start.addingTimeInterval(30),
                                                    cadenceStepsPerMinute: 100)
        let stale = matcher.locationUnavailable(at: start.addingTimeInterval(180),
                                                cadenceStepsPerMinute: nil)

        XCTAssertEqual(estimated.locationSource, .estimated)
        XCTAssertGreaterThan(estimated.routeProgressMeters, reliable.routeProgressMeters)
        XCTAssertNotNil(estimated.progressRangeStartMeters)
        XCTAssertNotNil(estimated.progressRangeEndMeters)
        XCTAssertEqual(estimated.lastReliableProgressMeters, reliable.lastReliableProgressMeters, accuracy: 0.01)
        XCTAssertEqual(stale.locationSource, .lastKnown)
        XCTAssertEqual(stale.confidence, .none)
        XCTAssertEqual(stale.routeProgressMeters, reliable.lastReliableProgressMeters, accuracy: 0.01)
    }

    @MainActor
    func testOfflineResourcesPersistPreparedRouteSeparatelyFromOriginalGPX() throws {
        let document = makeDocument([
            (27.0000, 114.0000, 100),
            (27.0010, 114.0000, 120)
        ])
        let prepared = try GPXRoutePreprocessor().prepare(document)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wudax-route-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = OfflineResourceManager(baseDirectory: directory)

        manager.prepare(analyzedGPX: GPXAnalyzer().analyze(document),
                        preparedRoute: prepared,
                        originalGPXData: Data("<gpx />".utf8))

        let preparedURL = try XCTUnwrap(manager.preparedRouteFileURL)
        let originalURL = try XCTUnwrap(manager.originalGPXFileURL)
        XCTAssertEqual(try JSONDecoder().decode(PreparedGPXRoute.self,
                                                from: Data(contentsOf: preparedURL)), prepared)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("<gpx />".utf8))
        XCTAssertTrue(manager.status.isReady)
    }

    private func makeDocument(_ values: [(Double, Double, Double)]) -> GPXDocument {
        let points = values.map { latitude, longitude, elevation in
            GPXTrackPoint(latitude: latitude,
                          longitude: longitude,
                          elevationMeters: elevation,
                          time: nil,
                          speedMetersPerSecond: nil,
                          heartRateBPM: nil,
                          cadenceRPM: nil)
        }
        return GPXDocument(name: "测试路线", creator: "tests",
                           segments: [GPXTrackSegment(points: points)], waypoints: [],
                           purpose: .plannedRoute)
    }

    private func input(latitude: Double, longitude: Double, accuracy: Double,
                       time: Date = Date(timeIntervalSince1970: 1_000),
                       speed: Double?, course: Double?) -> RouteLocationInput {
        RouteLocationInput(coordinate: RouteCoordinate(latitude: latitude, longitude: longitude),
                           horizontalAccuracyMeters: accuracy,
                           timestamp: time,
                           speedMetersPerSecond: speed,
                           courseDegrees: course,
                           altitudeMeters: nil,
                           cadenceStepsPerMinute: nil)
    }
}
