import SwiftUI
import MapKit

/// 地图相机只有在用户明确点击聚焦按钮时移动；`.automatic` 保持行中仪表盘的原有跟随行为。
enum RouteMapCameraMode: Equatable {
    case automatic
    case route
    case user
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .standard
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
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
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }

        let polyline = syncRoute(map, coordinates: coordinates, coordinator: context.coordinator)
        syncAccuracyCircle(map, coordinator: context.coordinator)
        syncMatchedAnnotation(map, coordinator: context.coordinator)
        syncUserAnnotation(map, coordinator: context.coordinator)
        updateCamera(map, polyline: polyline, coordinator: context.coordinator, fitRoute: fitRoute)
    }

    /// 只有路线本身变化时才重建折线与起终点，heading 高频更新不会让整张地图闪烁。
    private func syncRoute(_ map: MKMapView,
                           coordinates: [CLLocationCoordinate2D],
                           coordinator: Coordinator) -> MKPolyline {
        let key = RouteMapRouteKey(coordinates: coordinates)
        if coordinator.routeKey != key || coordinator.polyline == nil {
            if let polyline = coordinator.polyline { map.removeOverlay(polyline) }
            if let start = coordinator.startAnnotation { map.removeAnnotation(start) }
            if let end = coordinator.endAnnotation { map.removeAnnotation(end) }

            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            let start = RouteEndpointAnnotation(coordinate: coordinates[0], kind: .start)
            let end = RouteEndpointAnnotation(coordinate: coordinates[coordinates.count - 1], kind: .end)
            map.addOverlay(polyline)
            map.addAnnotations([start, end])

            coordinator.routeKey = key
            coordinator.polyline = polyline
            coordinator.startAnnotation = start
            coordinator.endAnnotation = end
        }

        if let renderer = map.renderer(for: coordinator.polyline!) as? MKPolylineRenderer {
            renderer.setNeedsDisplay()
        }
        return coordinator.polyline!
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
            if let currentCoordinate {
                map.setCenter(currentCoordinate, animated: true)
            } else if fitRoute {
                fit(polyline, on: map, animated: false)
            }

        case .route:
            let needsFocus = fitRoute || coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            guard needsFocus else { return }
            fit(polyline, on: map, animated: !fitRoute)
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID

        case .user:
            let needsFocus = coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            guard needsFocus, let currentCoordinate else { return }
            map.setRegion(
                MKCoordinateRegion(center: currentCoordinate,
                                   latitudinalMeters: 1_200,
                                   longitudinalMeters: 1_200),
                animated: true
            )
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID
        }
    }

    private func fit(_ polyline: MKPolyline, on map: MKMapView, animated: Bool) {
        map.setVisibleMapRect(polyline.boundingMapRect,
                              edgePadding: UIEdgeInsets(top: 130, left: 34, bottom: 230, right: 34),
                              animated: animated)
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
        var routeKey: RouteMapRouteKey?
        var polyline: MKPolyline?
        var accuracyKey: MapAccuracyKey?
        var accuracyCircle: MKCircle?
        var startAnnotation: RouteEndpointAnnotation?
        var endAnnotation: RouteEndpointAnnotation?
        var matchedAnnotation: MatchedRouteAnnotation?
        var userAnnotation: UserNavigationAnnotation?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
                marker.canShowCallout = true
                marker.glyphImage = UIImage(systemName: annotation.kind == .start ? "flag.fill" : "flag.checkered")
                marker.markerTintColor = annotation.kind == .start ? .systemGreen : .systemRed
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

private struct RouteMapRouteKey: Equatable {
    let count: Int
    let firstLatitude: CLLocationDegrees
    let firstLongitude: CLLocationDegrees
    let lastLatitude: CLLocationDegrees
    let lastLongitude: CLLocationDegrees

    init(coordinates: [CLLocationCoordinate2D]) {
        let first = coordinates[0]
        let last = coordinates[coordinates.count - 1]
        count = coordinates.count
        firstLatitude = first.latitude
        firstLongitude = first.longitude
        lastLatitude = last.latitude
        lastLongitude = last.longitude
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
    private let headingCone = CAShapeLayer()
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

        layer.addSublayer(headingCone)
        layer.addSublayer(halo)
        layer.addSublayer(whiteRing)
        layer.addSublayer(blueDot)
    }

    func update(headingDegrees: CLLocationDirection?) {
        guard let headingDegrees else {
            headingCone.path = nil
            return
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radians = CGFloat((headingDegrees - 90) * .pi / 180)
        let spread: CGFloat = .pi / 5
        let radius: CGFloat = 29
        let left = CGPoint(x: center.x + cos(radians - spread) * radius,
                           y: center.y + sin(radians - spread) * radius)
        let tip = CGPoint(x: center.x + cos(radians) * radius,
                          y: center.y + sin(radians) * radius)
        let right = CGPoint(x: center.x + cos(radians + spread) * radius,
                            y: center.y + sin(radians + spread) * radius)
        let path = UIBezierPath()
        path.move(to: center)
        path.addLine(to: left)
        path.addLine(to: tip)
        path.addLine(to: right)
        path.close()

        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = (headingCone.presentation() as? CAShapeLayer)?.path ?? headingCone.path
        animation.toValue = path.cgPath
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        headingCone.add(animation, forKey: "headingPath")
        headingCone.path = path.cgPath
        headingCone.fillColor = UIColor.systemBlue.withAlphaComponent(0.24).cgColor
    }
}
