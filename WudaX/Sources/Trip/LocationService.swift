@preconcurrency import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
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

    func requestBackgroundPermission() {
        guard manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    func startMonitoring() {
        requestPermission()
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        let hasBackgroundLocationMode = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let canUseBackgroundLocation = Self.shouldEnableBackgroundLocationUpdates(
            authorizationStatus: manager.authorizationStatus,
            hasBackgroundLocationMode: hasBackgroundLocationMode?.contains("location") == true
        )
        manager.allowsBackgroundLocationUpdates = canUseBackgroundLocation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isMonitoring = true
    }

    nonisolated static func shouldEnableBackgroundLocationUpdates(
        authorizationStatus: CLAuthorizationStatus,
        hasBackgroundLocationMode: Bool
    ) -> Bool {
        authorizationStatus == .authorizedAlways && hasBackgroundLocationMode
    }

    func stopMonitoring() {
        manager.stopUpdatingLocation()
        isMonitoring = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationState(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
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
