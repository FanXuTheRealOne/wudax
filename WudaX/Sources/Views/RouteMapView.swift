import SwiftUI
import MapKit

/// 地图相机只有在用户明确点击聚焦按钮时移动；`.automatic` 保持行中仪表盘的原有跟随行为。
enum RouteMapCameraMode: Equatable {
    case automatic
    /// 概览:路线与用户位置一屏同框(定位按钮循环的第一档)。
    case overview
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
    var tracksUserLocation = false
    var userHeadingDegrees: CLLocationDirection?
    var matchedCoordinate: RouteCoordinate?
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
        // 让 MapKit 自己管理 MKUserLocation，避免把 Core Location 坐标作为普通
        // annotation 重画后与中国区 Apple 底图产生显示链路差异。
        map.showsUserLocation = tracksUserLocation
        // 使用 MapKit 原生双指旋转；地图偏离正北后显示系统指南针，
        // 用户可以点击指南针快速回正，同时保留现有智能缩放与聚焦逻辑。
        map.showsCompass = tracksUserLocation
        map.showsScale = false
        map.isRotateEnabled = true
        map.isPitchEnabled = false
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

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        map.setUserTrackingMode(.none, animated: false)
        map.showsUserLocation = false
        map.delegate = nil
    }

    private func update(_ map: MKMapView, context: Context, fitRoute: Bool) {
        context.coordinator.fallbackHeadingDegrees = userHeadingDegrees
        if map.mapType != mapLayer.mapType {
            map.mapType = mapLayer.mapType
        }
        if map.showsUserLocation != tracksUserLocation {
            map.showsUserLocation = tracksUserLocation
        }
        if map.showsCompass != tracksUserLocation {
            map.showsCompass = tracksUserLocation
        }

        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }

        let polyline = syncRoute(map, coordinates: coordinates, coordinator: context.coordinator)
        context.coordinator.updateGuideLine(
            in: map,
            enabled: guideLineToStart,
            fallbackCurrentCoordinate: currentCoordinate,
            startCoordinate: coordinates.first
        )
        (map.view(for: map.userLocation) as? UserHeadingPuckView)?
            .update(headingDegrees: userHeadingDegrees)
        syncMatchedAnnotation(map, coordinator: context.coordinator)
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

        // 折线重绘只在偏航状态翻转时需要;heading/GPS 高频刷新不得逐帧触发
        // setNeedsDisplay,否则缩放手势期间整条折线持续重绘造成掉帧。
        if coordinator.lastRenderedOffRoute != isOffRoute {
            coordinator.lastRenderedOffRoute = isOffRoute
            if let renderer = map.renderer(for: coordinator.polyline!) as? MKPolylineRenderer {
                renderer.strokeColor = isOffRoute ? .systemOrange : UIColor(WDColor.bamboo)
                renderer.setNeedsDisplay()
            }
        }
        return coordinator.polyline!
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

    private func updateCamera(_ map: MKMapView,
                              polyline: MKPolyline,
                              coordinator: Coordinator,
                              fitRoute: Bool) {
        guard tracksUserLocation else {
            let needsFocus = fitRoute || !coordinator.hasSetInitialRegion
                || coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            guard needsFocus else { return }
            map.setUserTrackingMode(.none, animated: false)
            map.setRegion(paddedRegion(for: polyline.boundingMapRect, scale: 1.25), animated: !fitRoute)
            coordinator.hasSetInitialRegion = true
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID
            return
        }

        switch cameraMode {
        case .automatic:
            let explicitFocusRequest = coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            if explicitFocusRequest {
                coordinator.isFollowSuspendedByGesture = false
            }

            if guideLineToStart, let guide = coordinator.guidePolyline {
                // 前往起点阶段:首帧/显式定位时把自己与起点旗标一屏收进(缩放动画),
                // 不启用原生跟随以免相机立刻被拉回用户;之后缩放拖动交给用户。
                if explicitFocusRequest || !coordinator.hasSetGuideRegion {
                    map.setUserTrackingMode(.none, animated: false)
                    map.setRegion(paddedRegion(for: guide.boundingMapRect, scale: 1.6, minDelta: 0.008),
                                  animated: coordinator.hasSetInitialRegion)
                    coordinator.hasSetGuideRegion = true
                    coordinator.hasSetInitialRegion = true
                }
            } else if !coordinator.isFollowSuspendedByGesture {
                if map.userTrackingMode != .follow {
                    map.setUserTrackingMode(.follow, animated: coordinator.hasSetInitialRegion)
                }
                coordinator.hasSetUserRegion = map.userLocation.location != nil
            }

            if map.userLocation.location == nil,
               let currentCoordinate,
               CLLocationCoordinate2DIsValid(currentCoordinate),
               (explicitFocusRequest || !coordinator.hasSetUserRegion),
               !guideLineToStart {
                map.setRegion(
                    MKCoordinateRegion(center: currentCoordinate,
                                       latitudinalMeters: 1_500,
                                       longitudinalMeters: 1_500),
                    animated: coordinator.hasSetInitialRegion
                )
                coordinator.hasSetUserRegion = true
            } else if map.userLocation.location == nil,
                      currentCoordinate == nil,
                      !coordinator.hasSetInitialRegion {
                // 尚无定位:先展示整条路线。setRegion 在布局完成前调用也能正确生效,
                // 带 edgePadding 的 setVisibleMapRect 在零尺寸地图上会退化成全球视野。
                map.setRegion(paddedRegion(for: polyline.boundingMapRect, scale: 1.25), animated: false)
            }
            coordinator.hasSetInitialRegion = true
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID

        case .overview:
            // 概览:路线全貌 + 用户位置一屏同框,带缩放过渡动画。
            let needsFocus = fitRoute || coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            guard needsFocus else { return }
            map.setUserTrackingMode(.none, animated: false)
            coordinator.isFollowSuspendedByGesture = true
            var visibleRect = polyline.boundingMapRect
            if let userCoordinate = map.userLocation.location?.coordinate ?? currentCoordinate,
               CLLocationCoordinate2DIsValid(userCoordinate) {
                let point = MKMapPoint(userCoordinate)
                visibleRect = visibleRect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            map.setRegion(paddedRegion(for: visibleRect, scale: 1.25), animated: !fitRoute)
            coordinator.hasSetInitialRegion = true
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID

        case .route:
            let needsFocus = fitRoute || coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            guard needsFocus else { return }
            map.setUserTrackingMode(.none, animated: false)
            coordinator.isFollowSuspendedByGesture = true
            map.setRegion(paddedRegion(for: polyline.boundingMapRect, scale: 1.25), animated: !fitRoute)
            coordinator.hasSetInitialRegion = true
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID

        case .user:
            let explicitFocusRequest = coordinator.lastCameraMode != cameraMode
                || coordinator.lastCameraRequestID != cameraRequestID
            let needsFocus = explicitFocusRequest
                || (!coordinator.isFollowSuspendedByGesture && map.userTrackingMode != .follow)
            guard needsFocus else { return }
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID
            if explicitFocusRequest { coordinator.isFollowSuspendedByGesture = false }
            // 显式点击时先做可见的放大过渡(1.2 km 视野),再交给原生跟随;
            // 否则已处于 follow 时点击毫无视觉反馈。
            if explicitFocusRequest,
               let userCoordinate = map.userLocation.location?.coordinate ?? currentCoordinate,
               CLLocationCoordinate2DIsValid(userCoordinate) {
                map.setRegion(
                    MKCoordinateRegion(center: userCoordinate,
                                       latitudinalMeters: 1_200,
                                       longitudinalMeters: 1_200),
                    animated: true
                )
            }
            map.setUserTrackingMode(.follow, animated: true)
            coordinator.hasSetInitialRegion = true
            coordinator.hasSetUserRegion = map.userLocation.location != nil
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
        var lastRenderedOffRoute: Bool?
        var lastCameraMode: RouteMapCameraMode?
        var lastCameraRequestID: Int?
        var hasSetInitialRegion = false
        var hasSetUserRegion = false
        var hasSetGuideRegion = false
        var isFollowSuspendedByGesture = false
        var fallbackHeadingDegrees: CLLocationDirection?
        fileprivate var routeKey: RouteMapRouteKey?
        fileprivate var polyline: MKPolyline?
        fileprivate var guideKey: MapGuideKey?
        fileprivate var guidePolyline: GuidePolyline?
        fileprivate var startAnnotation: RouteEndpointAnnotation?
        fileprivate var endAnnotation: RouteEndpointAnnotation?
        fileprivate var matchedAnnotation: MatchedRouteAnnotation?
        private var guideEnabled = false
        private var guideFallbackCoordinate: CLLocationCoordinate2D?
        private var guideStartCoordinate: CLLocationCoordinate2D?

        func updateGuideLine(in mapView: MKMapView,
                             enabled: Bool,
                             fallbackCurrentCoordinate: CLLocationCoordinate2D?,
                             startCoordinate: CLLocationCoordinate2D?) {
            guideEnabled = enabled
            guideFallbackCoordinate = fallbackCurrentCoordinate
            guideStartCoordinate = startCoordinate

            let currentCoordinate = mapView.userLocation.location?.coordinate
                ?? fallbackCurrentCoordinate
            let key = MapGuideKey(enabled: enabled,
                                  currentCoordinate: currentCoordinate,
                                  startCoordinate: startCoordinate)
            guard guideKey != key else { return }

            if let guidePolyline { mapView.removeOverlay(guidePolyline) }
            guidePolyline = nil
            guideKey = key

            guard enabled, let currentCoordinate, let startCoordinate else { return }
            var guide = [currentCoordinate, startCoordinate]
            let guideCount = guide.count
            let polyline = GuidePolyline(coordinates: &guide, count: guideCount)
            mapView.addOverlay(polyline)
            guidePolyline = polyline
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            updateGuideLine(in: mapView,
                            enabled: guideEnabled,
                            fallbackCurrentCoordinate: guideFallbackCoordinate,
                            startCoordinate: guideStartCoordinate)
            guard let puck = mapView.view(for: userLocation) as? UserHeadingPuckView else { return }
            puck.update(headingDegrees: headingDegrees(from: userLocation) ?? fallbackHeadingDegrees)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard lastCameraMode != .route,
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

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            (mapView.view(for: mapView.userLocation) as? UserHeadingPuckView)?
                .updateConeRadius(headingConeRadius(in: mapView))
        }

        private func headingDegrees(from userLocation: MKUserLocation) -> CLLocationDirection? {
            guard let heading = userLocation.heading, heading.headingAccuracy >= 0 else { return nil }
            return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        }

        private func headingConeRadius(in mapView: MKMapView) -> CGFloat {
            guard mapView.bounds.width > 1,
                  !mapView.visibleMapRect.isNull,
                  !mapView.visibleMapRect.isEmpty else { return 27 }
            let metersAcross = mapView.visibleMapRect.size.width
                * MKMetersPerMapPointAtLatitude(mapView.centerCoordinate.latitude)
            let metersPerPoint = metersAcross / Double(mapView.bounds.width)
            guard metersPerPoint.isFinite, metersPerPoint > 0 else { return 27 }
            return min(max(CGFloat(110 / metersPerPoint), 16), 58)
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
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let identifier = "mapkit-user-location"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? UserHeadingPuckView)
                    ?? UserHeadingPuckView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.update(headingDegrees: headingDegrees(from: mapView.userLocation) ?? fallbackHeadingDegrees)
                view.updateConeRadius(headingConeRadius(in: mapView))
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
        // 端点坐标量化到约 30 m 网格：虚线是公里级起点引导，
        // GPS 逐秒漂移几米不值得删除重建 overlay，会打断缩放手势渲染。
        currentLatitude = Self.quantized(currentCoordinate?.latitude)
        currentLongitude = Self.quantized(currentCoordinate?.longitude)
        startLatitude = Self.quantized(startCoordinate?.latitude)
        startLongitude = Self.quantized(startCoordinate?.longitude)
    }

    private static func quantized(_ degrees: CLLocationDegrees?) -> CLLocationDegrees? {
        degrees.map { ($0 / 0.0003).rounded() * 0.0003 }
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

/// 附着在 MapKit 原生 MKUserLocation 上的方向标；坐标由 MapKit 管理，视图只负责外观。
private final class UserHeadingPuckView: MKAnnotationView {
    private let headingGradient = CAGradientLayer()
    private let headingMask = CAShapeLayer()
    private let halo = CAShapeLayer()
    private let whiteRing = CAShapeLayer()
    private let blueDot = CAShapeLayer()
    private var headingDegrees: CLLocationDirection?
    private var coneRadius: CGFloat = 27

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 132, height: 132)
        backgroundColor = .clear
        canShowCallout = false
        displayPriority = .required
        isUserInteractionEnabled = false
        setupLayers()
    }

    required init?(coder: NSCoder) { return nil }

    private func setupLayers() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        headingGradient.frame = bounds
        headingGradient.type = .radial
        headingGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        headingGradient.endPoint = CGPoint(x: 0.5 + coneRadius / bounds.width, y: 0.5)
        headingGradient.colors = [
            UIColor.systemBlue.withAlphaComponent(0.38).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.18).cgColor,
            UIColor.systemBlue.withAlphaComponent(0).cgColor
        ]
        headingGradient.locations = [0, 0.58, 1]
        headingMask.frame = bounds
        headingMask.fillColor = UIColor.white.cgColor
        headingGradient.mask = headingMask

        halo.path = UIBezierPath(ovalIn: CGRect(x: center.x - 16, y: center.y - 16,
                                                width: 32, height: 32)).cgPath
        halo.fillColor = UIColor.systemBlue.withAlphaComponent(0.14).cgColor
        whiteRing.path = UIBezierPath(ovalIn: CGRect(x: center.x - 11, y: center.y - 11,
                                                     width: 22, height: 22)).cgPath
        whiteRing.fillColor = UIColor.white.cgColor
        whiteRing.shadowColor = UIColor.black.withAlphaComponent(0.2).cgColor
        whiteRing.shadowRadius = 2
        whiteRing.shadowOffset = CGSize(width: 0, height: 1)
        whiteRing.shadowOpacity = 1
        blueDot.path = UIBezierPath(ovalIn: CGRect(x: center.x - 7, y: center.y - 7,
                                                   width: 14, height: 14)).cgPath
        blueDot.fillColor = UIColor.systemBlue.cgColor

        layer.addSublayer(headingGradient)
        layer.addSublayer(halo)
        layer.addSublayer(whiteRing)
        layer.addSublayer(blueDot)
    }

    func update(headingDegrees: CLLocationDirection?) {
        self.headingDegrees = headingDegrees
        redrawCone()
    }

    func updateConeRadius(_ radius: CGFloat) {
        let radius = min(max(radius, 16), 58)
        guard abs(radius - coneRadius) >= 0.5 else { return }
        coneRadius = radius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headingGradient.endPoint = CGPoint(x: 0.5 + coneRadius / bounds.width, y: 0.5)
        CATransaction.commit()
        redrawCone()
    }

    private func redrawCone() {
        guard let headingDegrees else {
            headingMask.path = nil
            return
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radians = CGFloat((headingDegrees - 90) * .pi / 180)
        let spread: CGFloat = .pi / 11
        let path = UIBezierPath()
        path.move(to: center)
        path.addArc(withCenter: center, radius: coneRadius,
                    startAngle: radians - spread, endAngle: radians + spread,
                    clockwise: true)
        path.close()

        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = (headingMask.presentation() as? CAShapeLayer)?.path ?? headingMask.path
        animation.toValue = path.cgPath
        animation.duration = 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        headingMask.add(animation, forKey: "headingPath")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headingMask.path = path.cgPath
        CATransaction.commit()
    }
}
