import SwiftUI
import MapKit

/// 地图相机只有在用户明确点击聚焦按钮时移动；`.automatic` 保持行中仪表盘的原有跟随行为。
enum RouteMapCameraMode: Equatable {
    case automatic
    case route
    case user
}

enum RouteMapLayer: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准"
        case .satellite: return "卫星"
        case .hybrid: return "混合"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas.fill"
        case .hybrid: return "square.3.layers.3d"
        }
    }

    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        }
    }
}

/// 本地 GPX 轨迹叠加层。底图是否可用由系统缓存决定，不能把在线瓦片假装成离线资源。
struct RouteMapView: UIViewRepresentable {
    let points: [GPXTrackPoint]
    var currentCoordinate: CLLocationCoordinate2D?
    var userHeadingDegrees: CLLocationDirection?
    var matchedCoordinate: RouteCoordinate?
    var horizontalAccuracyMeters: Double?
    var matchConfidence: RouteMatchConfidence?
    var isOffRoute = false
    var cameraMode: RouteMapCameraMode = .automatic
    var cameraRequestID = 0
    /// 在路线起终点画旗标(行中大地图用)。
    var showsEndpointFlags = false
    /// 尚未到达起点:从当前位置到路线起点画虚线引导。
    var guideLineToStart = false
    var mapLayer: RouteMapLayer = .standard

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = mapLayer.mapType
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isScrollEnabled = true
        map.isZoomEnabled = true
        map.pointOfInterestFilter = .excludingAll
        context.coordinator.isOffRoute = isOffRoute
        update(map, context: context, fitRoute: true)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.isOffRoute = isOffRoute
        update(map, context: context, fitRoute: context.coordinator.polyline == nil)
    }

    private func update(_ map: MKMapView, context: Context, fitRoute: Bool) {
        if map.mapType != mapLayer.mapType {
            map.mapType = mapLayer.mapType
        }

        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }

        let polyline = syncRoute(map, coordinates: coordinates, coordinator: context.coordinator)
        _ = syncGuideLine(map, coordinates: coordinates, coordinator: context.coordinator)
        syncAccuracyCircle(map, coordinator: context.coordinator)
        syncMatchedAnnotation(map, coordinator: context.coordinator)
        syncUserAnnotation(map, coordinator: context.coordinator)
        updateCamera(map, polyline: polyline, coordinator: context.coordinator, fitRoute: fitRoute)
    }

    /// 只有路线本身变化时才重建折线与起终点，heading 高频更新不会让整张地图闪烁。
    private func syncRoute(_ map: MKMapView,
                           coordinates: [CLLocationCoordinate2D],
                           coordinator: Coordinator) -> MKPolyline {
        let key = RouteMapRouteKey(coordinates: coordinates, showsEndpointFlags: showsEndpointFlags)
        if coordinator.routeKey != key || coordinator.polyline == nil {
            if let polyline = coordinator.polyline { map.removeOverlay(polyline) }
            if let start = coordinator.startAnnotation { map.removeAnnotation(start) }
            if let end = coordinator.endAnnotation { map.removeAnnotation(end) }

            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            map.addOverlay(polyline)

            coordinator.routeKey = key
            coordinator.polyline = polyline
            coordinator.startAnnotation = nil
            coordinator.endAnnotation = nil

            if showsEndpointFlags {
                let startCoordinate = coordinates[0]
                let endCoordinate = coordinates[coordinates.count - 1]
                let start = RouteEndpointAnnotation(coordinate: startCoordinate, kind: .start)
                map.addAnnotation(start)
                coordinator.startAnnotation = start

                let separation = CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
                    .distance(from: CLLocation(latitude: endCoordinate.latitude, longitude: endCoordinate.longitude))
                if separation > 30 {
                    let end = RouteEndpointAnnotation(coordinate: endCoordinate, kind: .end)
                    map.addAnnotation(end)
                    coordinator.endAnnotation = end
                }
            }
        }

        if let renderer = map.renderer(for: coordinator.polyline!) as? MKPolylineRenderer {
            renderer.setNeedsDisplay()
        }
        return coordinator.polyline!
    }

    private func syncGuideLine(_ map: MKMapView,
                               coordinates: [CLLocationCoordinate2D],
                               coordinator: Coordinator) -> GuidePolyline? {
        let startCoordinate = coordinates.first
        let key = MapGuideKey(enabled: guideLineToStart,
                              currentCoordinate: currentCoordinate,
                              startCoordinate: startCoordinate)
        guard coordinator.guideKey != key else { return coordinator.guidePolyline }

        if let guidePolyline = coordinator.guidePolyline { map.removeOverlay(guidePolyline) }
        coordinator.guidePolyline = nil
        coordinator.guideKey = key

        guard guideLineToStart, let currentCoordinate, let startCoordinate else { return nil }
        var guide = [currentCoordinate, startCoordinate]
        let guideCount = guide.count
        let guidePolyline = GuidePolyline(coordinates: &guide, count: guideCount)
        map.addOverlay(guidePolyline)
        coordinator.guidePolyline = guidePolyline
        return guidePolyline
    }

    private func syncAccuracyCircle(_ map: MKMapView, coordinator: Coordinator) {
        let key = MapAccuracyKey(coordinate: currentCoordinate, accuracyMeters: horizontalAccuracyMeters)
        guard coordinator.accuracyKey != key else { return }
        if let circle = coordinator.accuracyCircle { map.removeOverlay(circle) }
        coordinator.accuracyCircle = nil
        coordinator.accuracyKey = key

        if let currentCoordinate,
           let horizontalAccuracyMeters,
           horizontalAccuracyMeters.isFinite,
           horizontalAccuracyMeters > 0 {
            let circle = MKCircle(center: currentCoordinate, radius: min(horizontalAccuracyMeters, 500))
            map.addOverlay(circle)
            coordinator.accuracyCircle = circle
        }
    }

    private func syncMatchedAnnotation(_ map: MKMapView, coordinator: Coordinator) {
        guard let matchedCoordinate else {
            if let annotation = coordinator.matchedAnnotation { map.removeAnnotation(annotation) }
            coordinator.matchedAnnotation = nil
            return
        }

        let coordinate = CLLocationCoordinate2D(latitude: matchedCoordinate.latitude, longitude: matchedCoordinate.longitude)
        if let annotation = coordinator.matchedAnnotation {
            annotation.coordinate = coordinate
            annotation.confidence = matchConfidence
            annotation.isOffRoute = isOffRoute
            if let marker = map.view(for: annotation) as? MKMarkerAnnotationView {
                marker.glyphImage = UIImage(systemName: annotation.confidence == RouteMatchConfidence.none ? "questionmark" : "figure.hiking")
                marker.markerTintColor = markerTint(for: annotation)
            }
        } else {
            let annotation = MatchedRouteAnnotation(coordinate: coordinate,
                                                    confidence: matchConfidence,
                                                    isOffRoute: isOffRoute)
            coordinator.matchedAnnotation = annotation
            map.addAnnotation(annotation)
        }
    }

    private func syncUserAnnotation(_ map: MKMapView, coordinator: Coordinator) {
        guard let currentCoordinate else {
            if let annotation = coordinator.userAnnotation { map.removeAnnotation(annotation) }
            coordinator.userAnnotation = nil
            return
        }

        if let annotation = coordinator.userAnnotation {
            annotation.coordinate = currentCoordinate
            annotation.headingDegrees = userHeadingDegrees
            (map.view(for: annotation) as? UserNavigationPuckView)?.update(headingDegrees: userHeadingDegrees)
        } else {
            let annotation = UserNavigationAnnotation(coordinate: currentCoordinate, headingDegrees: userHeadingDegrees)
            coordinator.userAnnotation = annotation
            map.addAnnotation(annotation)
        }
    }

    private func updateCamera(_ map: MKMapView,
                              polyline: MKPolyline,
                              coordinator: Coordinator,
                              fitRoute: Bool) {
        switch cameraMode {
        case .automatic:
            let explicitFocusRequest = coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            if explicitFocusRequest {
                coordinator.isFollowSuspendedByGesture = false
                if currentCoordinate == nil { coordinator.hasSetUserRegion = false }
            }

            if let currentCoordinate,
               CLLocationCoordinate2DIsValid(currentCoordinate) {
                let previousLocation = coordinator.lastFollowCoordinate.map {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                }
                let currentLocation = CLLocation(latitude: currentCoordinate.latitude,
                                                 longitude: currentCoordinate.longitude)
                let movedEnough = previousLocation.map { currentLocation.distance(from: $0) >= 8 } ?? true

                if explicitFocusRequest || !coordinator.hasSetUserRegion {
                    map.setRegion(
                        MKCoordinateRegion(center: currentCoordinate,
                                           latitudinalMeters: 1_500,
                                           longitudinalMeters: 1_500),
                        animated: coordinator.hasSetInitialRegion
                    )
                    coordinator.hasSetUserRegion = true
                    coordinator.lastFollowCoordinate = currentCoordinate
                } else if !coordinator.isFollowSuspendedByGesture && movedEnough {
                    // 仅在 GPS 位置真正移动时更新中心，罗盘高频刷新不会再触发地图动画。
                    map.setCenter(currentCoordinate, animated: false)
                    coordinator.lastFollowCoordinate = currentCoordinate
                }
            } else if !coordinator.hasSetInitialRegion {
                // 尚无定位:先展示整条路线。setRegion 在布局完成前调用也能正确生效,
                // 带 edgePadding 的 setVisibleMapRect 在零尺寸地图上会退化成全球视野。
                map.setRegion(paddedRegion(for: polyline.boundingMapRect, scale: 1.25), animated: false)
            }
            coordinator.hasSetInitialRegion = true
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID

        case .route:
            let needsFocus = fitRoute || coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            guard needsFocus else { return }
            map.setRegion(paddedRegion(for: polyline.boundingMapRect, scale: 1.25), animated: !fitRoute)
            coordinator.hasSetInitialRegion = true
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID

        case .user:
            let needsFocus = coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
                || !coordinator.hasSetUserRegion
            guard needsFocus else { return }
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID
            guard let currentCoordinate,
                  CLLocationCoordinate2DIsValid(currentCoordinate) else {
                coordinator.hasSetUserRegion = false
                return
            }
            map.setRegion(
                MKCoordinateRegion(center: currentCoordinate,
                                   latitudinalMeters: 1_200,
                                   longitudinalMeters: 1_200),
                animated: true
            )
            coordinator.hasSetInitialRegion = true
            coordinator.hasSetUserRegion = true
        }
    }

    /// 由 boundingMapRect 计算带边距的 region,避免依赖地图已布局的 edgePadding fit。
    private func paddedRegion(for rect: MKMapRect, scale: Double, minDelta: Double = 0) -> MKCoordinateRegion {
        var region = MKCoordinateRegion(rect)
        region.span.latitudeDelta = min(max(region.span.latitudeDelta * scale, minDelta), 160)
        region.span.longitudeDelta = min(max(region.span.longitudeDelta * scale, minDelta), 340)
        return region
    }

    private func markerTint(for annotation: MatchedRouteAnnotation) -> UIColor {
        annotation.isOffRoute ? .systemRed
            : annotation.confidence == .low ? .systemOrange
            : UIColor(WDColor.bamboo)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var isOffRoute = false
        var lastCameraMode: RouteMapCameraMode?
        var lastCameraRequestID: Int?
        var hasSetInitialRegion = false
        var hasSetUserRegion = false
        var isFollowSuspendedByGesture = false
        var lastFollowCoordinate: CLLocationCoordinate2D?
        fileprivate var routeKey: RouteMapRouteKey?
        fileprivate var polyline: MKPolyline?
        fileprivate var guideKey: MapGuideKey?
        fileprivate var guidePolyline: GuidePolyline?
        fileprivate var accuracyKey: MapAccuracyKey?
        fileprivate var accuracyCircle: MKCircle?
        fileprivate var startAnnotation: RouteEndpointAnnotation?
        fileprivate var endAnnotation: RouteEndpointAnnotation?
        fileprivate var matchedAnnotation: MatchedRouteAnnotation?
        fileprivate var userAnnotation: UserNavigationAnnotation?

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard lastCameraMode == .automatic,
                  containsActiveGesture(in: mapView) else { return }
            isFollowSuspendedByGesture = true
        }

        private func containsActiveGesture(in view: UIView) -> Bool {
            if (view.gestureRecognizers ?? []).contains(where: {
                $0.state == .began || $0.state == .changed
            }) {
                return true
            }
            return view.subviews.contains { containsActiveGesture(in: $0) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let guide = overlay as? GuidePolyline {
                let renderer = MKPolylineRenderer(polyline: guide)
                renderer.strokeColor = UIColor(WDColor.amber)
                renderer.lineWidth = 3
                renderer.lineDashPattern = [8, 6]
                renderer.lineJoin = .round
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = isOffRoute ? .systemOrange : UIColor(WDColor.bamboo)
                renderer.lineWidth = 4
                renderer.lineJoin = .round
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.10)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.45)
                renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let annotation = annotation as? UserNavigationAnnotation {
                let identifier = "user-navigation-puck"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? UserNavigationPuckView)
                    ?? UserNavigationPuckView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.update(headingDegrees: annotation.headingDegrees)
                return view
            }

            if let annotation = annotation as? RouteEndpointAnnotation {
                let identifier = "route-endpoint-\(annotation.kind.rawValue)"
                let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                marker.annotation = annotation
                marker.canShowCallout = false
                marker.glyphImage = UIImage(systemName: annotation.kind == .start ? "flag.fill" : "flag.checkered")
                marker.markerTintColor = annotation.kind == .start ? UIColor(WDColor.bamboo) : UIColor(WDColor.ink)
                marker.displayPriority = .required
                return marker
            }

            guard let annotation = annotation as? MatchedRouteAnnotation else { return nil }
            let identifier = "matched-route-position"
            let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            marker.annotation = annotation
            marker.canShowCallout = true
            marker.glyphImage = UIImage(systemName: annotation.confidence == RouteMatchConfidence.none ? "questionmark" : "figure.hiking")
            marker.markerTintColor = annotation.isOffRoute ? .systemRed
                : annotation.confidence == .low ? .systemOrange
                : UIColor(WDColor.bamboo)
            return marker
        }
    }
}

/// 用户当前位置 → 路线起点的虚线引导(区别于主路线实线)。
private final class GuidePolyline: MKPolyline {}

private struct RouteMapRouteKey: Equatable {
    let count: Int
    let firstLatitude: CLLocationDegrees
    let firstLongitude: CLLocationDegrees
    let lastLatitude: CLLocationDegrees
    let lastLongitude: CLLocationDegrees
    let showsEndpointFlags: Bool

    init(coordinates: [CLLocationCoordinate2D], showsEndpointFlags: Bool) {
        let first = coordinates[0]
        let last = coordinates[coordinates.count - 1]
        count = coordinates.count
        firstLatitude = first.latitude
        firstLongitude = first.longitude
        lastLatitude = last.latitude
        lastLongitude = last.longitude
        self.showsEndpointFlags = showsEndpointFlags
    }
}

private struct MapGuideKey: Equatable {
    let enabled: Bool
    let currentLatitude: CLLocationDegrees?
    let currentLongitude: CLLocationDegrees?
    let startLatitude: CLLocationDegrees?
    let startLongitude: CLLocationDegrees?

    init(enabled: Bool,
         currentCoordinate: CLLocationCoordinate2D?,
         startCoordinate: CLLocationCoordinate2D?) {
        self.enabled = enabled
        currentLatitude = currentCoordinate?.latitude
        currentLongitude = currentCoordinate?.longitude
        startLatitude = startCoordinate?.latitude
        startLongitude = startCoordinate?.longitude
    }
}

private struct MapAccuracyKey: Equatable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?
    let radius: Double?

    init(coordinate: CLLocationCoordinate2D?, accuracyMeters: Double?) {
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
        radius = accuracyMeters.map { min($0, 500).rounded() }
    }
}

private final class MatchedRouteAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var confidence: RouteMatchConfidence?
    var isOffRoute: Bool
    var title: String? { isOffRoute ? "可能偏离路线" : "路线匹配位置" }

    init(coordinate: CLLocationCoordinate2D, confidence: RouteMatchConfidence?, isOffRoute: Bool) {
        self.coordinate = coordinate
        self.confidence = confidence
        self.isOffRoute = isOffRoute
    }
}

private final class UserNavigationAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var headingDegrees: CLLocationDirection?

    init(coordinate: CLLocationCoordinate2D, headingDegrees: CLLocationDirection?) {
        self.coordinate = coordinate
        self.headingDegrees = headingDegrees
    }
}

private enum RouteEndpoint: String {
    case start
    case end
}

private final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let kind: RouteEndpoint
    var title: String? { kind == .start ? "起点" : "终点" }

    init(coordinate: CLLocationCoordinate2D, kind: RouteEndpoint) {
        self.coordinate = coordinate
        self.kind = kind
    }
}

/// 参考 Apple 地图的定位 puck：蓝色圆点、白色外环与半透明朝向扇形。
/// 不替换 annotation 实例，只更新 CALayer 路径，从而避免 heading 更新时闪烁。
private final class UserNavigationPuckView: MKAnnotationView {
    private let headingGradient = CAGradientLayer()
    private let headingConeMask = CAShapeLayer()
    private let halo = CAShapeLayer()
    private let whiteRing = CAShapeLayer()
    private let blueDot = CAShapeLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 58, height: 58)
        centerOffset = .zero
        backgroundColor = .clear
        canShowCallout = false
        isOpaque = false
        setupLayers()
    }

    required init?(coder: NSCoder) { return nil }

    private func setupLayers() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        headingGradient.frame = bounds
        headingGradient.type = .radial
        headingGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        headingGradient.endPoint = CGPoint(x: 0.96, y: 0.5)
        headingGradient.colors = [
            UIColor.systemBlue.withAlphaComponent(0.34).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.18).cgColor,
            UIColor.systemBlue.withAlphaComponent(0).cgColor
        ]
        headingGradient.locations = [0, 0.52, 1]
        headingConeMask.frame = headingGradient.bounds
        headingGradient.mask = headingConeMask

        halo.path = UIBezierPath(ovalIn: CGRect(x: center.x - 17, y: center.y - 17, width: 34, height: 34)).cgPath
        halo.fillColor = UIColor.systemBlue.withAlphaComponent(0.16).cgColor

        whiteRing.path = UIBezierPath(ovalIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)).cgPath
        whiteRing.fillColor = UIColor.white.cgColor
        whiteRing.shadowColor = UIColor.black.withAlphaComponent(0.22).cgColor
        whiteRing.shadowRadius = 2
        whiteRing.shadowOffset = CGSize(width: 0, height: 1)
        whiteRing.shadowOpacity = 1

        blueDot.path = UIBezierPath(ovalIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).cgPath
        blueDot.fillColor = UIColor.systemBlue.cgColor
        blueDot.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        blueDot.lineWidth = 1.2

        layer.addSublayer(headingGradient)
        layer.addSublayer(halo)
        layer.addSublayer(whiteRing)
        layer.addSublayer(blueDot)
    }

    func update(headingDegrees: CLLocationDirection?) {
        guard let headingDegrees else {
            headingConeMask.removeAllAnimations()
            headingConeMask.path = nil
            return
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radians = CGFloat((headingDegrees - 90) * .pi / 180)
        let spread: CGFloat = .pi / 10
        let radius: CGFloat = 27
        let path = UIBezierPath()
        path.move(to: center)
        path.addArc(withCenter: center,
                    radius: radius,
                    startAngle: radians - spread,
                    endAngle: radians + spread,
                    clockwise: true)
        path.close()

        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = (headingConeMask.presentation() as? CAShapeLayer)?.path ?? headingConeMask.path
        animation.toValue = path.cgPath
        animation.duration = 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        headingConeMask.add(animation, forKey: "headingPath")
        headingConeMask.path = path.cgPath
        headingConeMask.fillColor = UIColor.white.cgColor
    }
}
