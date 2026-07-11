@preconcurrency import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum MonitoringMode {
        case browsing
        case activeHike
    }

    enum AuthorizationState: Equatable {
        case notDetermined, whenInUse, always, denied, restricted
    }

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published private(set) var latestRawLocation: CLLocation?
    @Published private(set) var latestLocation: CLLocation?
    private(set) var latestHeading: CLHeading?
    @Published private(set) var headingDegrees: CLLocationDirection?
    @Published private(set) var isMonitoring = false
    var onLocationUpdate: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private var monitoringMode: MonitoringMode = .browsing
    private let maximumReliableHorizontalAccuracy: CLLocationAccuracy = 100

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        // 地图导航需要连续朝向；后续用低通滤波消除罗盘抖动，而不是粗粒度丢弃更新。
        manager.headingFilter = kCLHeadingFilterNone
        updateAuthorizationState(manager.authorizationStatus)
        accuracyAuthorization = manager.accuracyAuthorization
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestBackgroundPermission() {
        guard manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    func startMonitoring(mode: MonitoringMode = .browsing) {
        let startsNewSession = !isMonitoring || monitoringMode != mode
        monitoringMode = mode
        if startsNewSession {
            latestRawLocation = nil
            latestLocation = nil
        }
        requestPermission()
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        configureLocationUpdates(for: mode)
        let hasBackgroundLocationMode = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let canUseBackgroundLocation = Self.shouldEnableBackgroundLocationUpdates(
            authorizationStatus: manager.authorizationStatus,
            hasBackgroundLocationMode: hasBackgroundLocationMode?.contains("location") == true
        )
        manager.allowsBackgroundLocationUpdates = canUseBackgroundLocation
        manager.showsBackgroundLocationIndicator = canUseBackgroundLocation
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        isMonitoring = true
    }

    private func configureLocationUpdates(for mode: MonitoringMode) {
        switch mode {
        case .browsing:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 5
            manager.pausesLocationUpdatesAutomatically = true
        case .activeHike:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = 1
            manager.pausesLocationUpdatesAutomatically = false
        }
    }

    nonisolated static func shouldEnableBackgroundLocationUpdates(
        authorizationStatus: CLAuthorizationStatus,
        hasBackgroundLocationMode: Bool
    ) -> Bool {
        authorizationStatus == .authorizedAlways && hasBackgroundLocationMode
    }

    func stopMonitoring() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isMonitoring = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationState(manager.authorizationStatus)
        accuracyAuthorization = manager.accuracyAuthorization
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startMonitoring(mode: monitoringMode)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date()
        guard let location = locations.reversed().first(where: {
            $0.horizontalAccuracy >= 0 &&
            now.timeIntervalSince($0.timestamp) <= 15 &&
            CLLocationCoordinate2DIsValid($0.coordinate)
        }) else { return }
        latestRawLocation = location
        guard location.horizontalAccuracy <= maximumReliableHorizontalAccuracy else { return }
        latestLocation = location
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        latestHeading = newHeading
        let rawHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        headingDegrees = smoothedHeading(from: rawHeading, previous: headingDegrees)
    }

    /// 以最短角度路径平滑朝向，避免 359° → 0° 时发生反向跳转。
    private func smoothedHeading(from raw: CLLocationDirection,
                                 previous: CLLocationDirection?) -> CLLocationDirection {
        guard let previous else { return raw }
        let delta = (raw - previous + 540).truncatingRemainder(dividingBy: 360) - 180
        let smoothed = (previous + delta * 0.35).truncatingRemainder(dividingBy: 360)
        return smoothed < 0 ? smoothed + 360 : smoothed
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
