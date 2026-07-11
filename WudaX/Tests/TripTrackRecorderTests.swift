import XCTest
import CoreLocation
@testable import WudaX

final class TripTrackRecorderTests: XCTestCase {
    func testBundledExoskeletonSceneLoads() {
        XCTAssertNotNil(ExoModelResource.scene())
    }

    func testWorkoutClockExcludesPausedInterval() {
        let clock = WorkoutElapsedClock(startDate: Date(timeIntervalSince1970: 1_000))
        clock.pause(at: Date(timeIntervalSince1970: 1_600))
        XCTAssertEqual(clock.elapsedSeconds(at: Date(timeIntervalSince1970: 2_200)), 600, accuracy: 0.001)
        clock.resume(at: Date(timeIntervalSince1970: 2_800))
        XCTAssertEqual(clock.elapsedSeconds(at: Date(timeIntervalSince1970: 3_400)), 1_200, accuracy: 0.001)
    }

    func testWorkoutPaceFormatterAvoidsFakeSpeed() {
        XCTAssertEqual(formatWorkoutPace(distanceKm: 0, elapsedHours: 1), "—")
        XCTAssertEqual(formatWorkoutPace(distanceKm: 5, elapsedHours: 1), "12′00″/km")
    }

    func testMapFollowDecisionIgnoresJitterAndGestureSuspension() {
        XCTAssertFalse(MapFollowDecision.shouldRecenter(distanceMeters: 3, secondsSinceLastUpdate: 1,
                                                        isSuspended: false, isExplicit: false))
        XCTAssertFalse(MapFollowDecision.shouldRecenter(distanceMeters: 30, secondsSinceLastUpdate: 1,
                                                        isSuspended: true, isExplicit: false))
        XCTAssertTrue(MapFollowDecision.shouldRecenter(distanceMeters: 30, secondsSinceLastUpdate: 1,
                                                       isSuspended: false, isExplicit: false))
        XCTAssertTrue(MapFollowDecision.shouldRecenter(distanceMeters: 0, secondsSinceLastUpdate: 0,
                                                       isSuspended: true, isExplicit: true))
    }

    func testLocationFocusCyclesOverviewThenUser() {
        XCTAssertEqual(LocationFocusCycle.next(after: .automatic), .overview)
        XCTAssertEqual(LocationFocusCycle.next(after: .overview), .user)
        XCTAssertEqual(LocationFocusCycle.next(after: .user), .overview)
    }

    @MainActor
    func testRecordsRealLocationSamplesAndFiltersJumps() {
        let recorder = TripTrackRecorder()
        recorder.start()
        recorder.append(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 27, longitude: 114),
                                   altitude: 100, horizontalAccuracy: 5, verticalAccuracy: 5,
                                   timestamp: Date()))
        recorder.append(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 27.0001, longitude: 114),
                                   altitude: 101, horizontalAccuracy: 5, verticalAccuracy: 5,
                                   timestamp: Date().addingTimeInterval(10)))
        recorder.append(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 28, longitude: 115),
                                   altitude: 101, horizontalAccuracy: 5, verticalAccuracy: 5,
                                   timestamp: Date().addingTimeInterval(20)))

        XCTAssertEqual(recorder.points.count, 3)
        XCTAssertGreaterThan(recorder.distanceMeters, 5)
        XCTAssertLessThan(recorder.distanceMeters, 250)
    }

    @MainActor
    func testResumeStartsANewDistanceSegmentAfterPause() {
        let recorder = TripTrackRecorder()
        recorder.start()
        recorder.append(CLLocation(latitude: 27, longitude: 114))
        recorder.stop()
        recorder.startKeepingHistory()
        recorder.append(CLLocation(latitude: 27.001, longitude: 114))

        XCTAssertEqual(recorder.distanceMeters, 0, accuracy: 0.001)
        XCTAssertEqual(recorder.points.count, 2)
    }
}
