import Combine
import CoreLocation
import Foundation

@MainActor
final class HikeLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isTracking = false

    private let manager = CLLocationManager()
    private var shouldTrackAfterAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8
        manager.pausesLocationUpdatesAutomatically = true
    }

    func startTracking() {
        shouldTrackAfterAuthorization = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            isTracking = true
        case .denied, .restricted:
            errorMessage = "未获得定位权限，无法将当前位置匹配到路线"
        @unknown default:
            errorMessage = "当前定位权限状态不受支持"
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
        shouldTrackAfterAuthorization = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard shouldTrackAfterAuthorization else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            isTracking = true
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            errorMessage = "未获得定位权限，无法将当前位置匹配到路线"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        latestLocation = location
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}
