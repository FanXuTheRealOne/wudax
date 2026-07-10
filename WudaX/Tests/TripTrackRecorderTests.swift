import XCTest
import CoreLocation
@testable import WudaX

final class TripTrackRecorderTests: XCTestCase {
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
}
