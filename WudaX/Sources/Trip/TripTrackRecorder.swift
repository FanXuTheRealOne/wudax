import Foundation
import CoreLocation
import Combine

@MainActor
final class TripTrackRecorder: ObservableObject {
    @Published private(set) var points: [RecordedTrackPoint] = []
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var isRecording = false

    func start() {
        points = []
        distanceMeters = 0
        isRecording = true
    }

    func append(_ location: CLLocation) {
        guard isRecording, location.horizontalAccuracy >= 0 else { return }
        if let previous = points.last {
            let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let delta = location.distance(from: previousLocation)
            // Filter GPS jumps while retaining slow hiking movement.
            if delta > 0, delta < 250 { distanceMeters += delta }
        }
        points.append(RecordedTrackPoint(latitude: location.coordinate.latitude,
                                         longitude: location.coordinate.longitude,
                                         elevationMeters: location.altitude >= 0 ? location.altitude : nil,
                                         timestamp: location.timestamp,
                                         horizontalAccuracyMeters: location.horizontalAccuracy))
    }

    func stop() { isRecording = false }
}
