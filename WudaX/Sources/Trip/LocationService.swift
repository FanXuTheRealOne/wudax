import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum AuthorizationState: Equatable {
        case notDetermined, whenInUse, always, denied, restricted
    }

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var isMonitoring = false
    var onLocationUpdate: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        updateAuthorizationState(manager.authorizationStatus)
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startMonitoring() {
        requestPermission()
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        isMonitoring = true
    }

    func stopMonitoring() {
        manager.stopUpdatingLocation()
        isMonitoring = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationState(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startMonitoring()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        latestLocation = location
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 保留最后一个可信位置；UI 由 isMonitoring 和授权状态表达降级。
    }

    private func updateAuthorizationState(_ status: CLAuthorizationStatus) {
        authorizationState = switch status {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }
}
