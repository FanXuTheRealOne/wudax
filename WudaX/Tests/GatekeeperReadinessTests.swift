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
