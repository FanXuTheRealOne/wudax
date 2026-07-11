import XCTest
@testable import WudaX

final class GatekeeperReadinessTests: XCTestCase {
    func testAllReadyProducesNoReminders() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: true,
            locationAuthorized: true,
            notificationsAuthorized: true
        )

        XCTAssertEqual(readiness.notices, [])
    }

    func testOnlyMissingLocationProducesLocationReminder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: true,
            locationAuthorized: false,
            notificationsAuthorized: true
        )

        XCTAssertEqual(readiness.notices, [.locationPermission])
    }

    func testOnlyMissingNotificationProducesNotificationReminder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: true,
            locationAuthorized: true,
            notificationsAuthorized: false
        )

        XCTAssertEqual(readiness.notices, [.notificationPermission])
    }

    func testOnlyMissingOfflineResourcesProducesOfflineReminder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: false,
            locationAuthorized: true,
            notificationsAuthorized: true
        )

        XCTAssertEqual(readiness.notices, [.offlineResources])
    }

    func testMissingItemsUseStableDisplayOrder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: false,
            locationAuthorized: false,
            notificationsAuthorized: false
        )

        XCTAssertEqual(
            readiness.notices,
            [.offlineResources, .locationPermission, .notificationPermission]
        )
    }
}

final class TripStartGateTests: XCTestCase {
    func testRequiresTwoReliableFixesAtRouteStart() {
        var gate = TripStartGate()

        XCTAssertFalse(gate.register(distanceMeters: 20, horizontalAccuracyMeters: 12))
        XCTAssertTrue(gate.register(distanceMeters: 18, horizontalAccuracyMeters: 10))
    }

    func testPoorAccuracyCannotStartTrip() {
        var gate = TripStartGate()

        XCTAssertFalse(gate.register(distanceMeters: 10, horizontalAccuracyMeters: 80))
        XCTAssertFalse(gate.register(distanceMeters: 10, horizontalAccuracyMeters: 80))
        XCTAssertEqual(gate.consecutiveFixes, 0)
    }

    func testLeavingStartAreaResetsConsecutiveFixes() {
        var gate = TripStartGate()

        XCTAssertFalse(gate.register(distanceMeters: 25, horizontalAccuracyMeters: 15))
        XCTAssertFalse(gate.register(distanceMeters: 90, horizontalAccuracyMeters: 15))
        XCTAssertFalse(gate.register(distanceMeters: 25, horizontalAccuracyMeters: 15))
        XCTAssertTrue(gate.register(distanceMeters: 24, horizontalAccuracyMeters: 15))
    }
}
