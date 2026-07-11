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
    var tracksUserLocation = false
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

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        map.setUserTrackingMode(.none, animated: false)
        map.showsUserLocation = false
        map.delegate = nil
    }

    private func update(_ map: MKMapView, context: Context, fitRoute: Bool) {
        if map.mapType != mapLayer.mapType {
            map.mapType = mapLayer.mapType
        }
        if map.showsUserLocation != tracksUserLocation {
            map.showsUserLocation = tracksUserLocation
        }

        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }

        let polyline = syncRoute(map, coordinates: coordinates, coordinator: context.coordinator)
        _ = syncGuideLine(map, coordinates: coordinates, coordinator: context.coordinator)
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

            if !coordinator.isFollowSuspendedByGesture {
                if map.userTrackingMode != .follow {
                    map.setUserTrackingMode(.follow, animated: coordinator.hasSetInitialRegion)
                }
                coordinator.hasSetUserRegion = map.userLocation.location != nil
            }

            if map.userLocation.location == nil,
               let currentCoordinate,
               CLLocationCoordinate2DIsValid(currentCoordinate),
               (explicitFocusRequest || !coordinator.hasSetUserRegion) {
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
        var lastCameraMode: RouteMapCameraMode?
        var lastCameraRequestID: Int?
        var hasSetInitialRegion = false
        var hasSetUserRegion = false
        var isFollowSuspendedByGesture = false
        fileprivate var routeKey: RouteMapRouteKey?
        fileprivate var polyline: MKPolyline?
        fileprivate var guideKey: MapGuideKey?
        fileprivate var guidePolyline: GuidePolyline?
        fileprivate var startAnnotation: RouteEndpointAnnotation?
        fileprivate var endAnnotation: RouteEndpointAnnotation?
        fileprivate var matchedAnnotation: MatchedRouteAnnotation?

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
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKUserLocationView)
                    ?? MKUserLocationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
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

enum LocationFocusCycle {
    static func next(after mode: RouteMapCameraMode) -> RouteMapCameraMode {
        switch mode {
        case .route, .user:
            return .automatic
        case .automatic:
            return .user
        }
    }
}

// MARK: - 地图相机控制按钮组(行中页与主地图页共用)
// 「路线聚焦」+「定位循环」:定位按钮第一次点进入自动态，
// 再点切换为跟随定位；相机动画由 RouteMapView.updateCamera 统一执行。
struct MapCameraControls: View {
    @Binding var cameraMode: RouteMapCameraMode
    @Binding var cameraRequestID: Int
    /// 点定位按钮时的附加动作(主地图页用来启动定位监听)。
    var onLocateTapped: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            MapControlButton(icon: "arrow.up.left.and.arrow.down.right",
                             selected: cameraMode == .route) {
                cameraMode = .route
                cameraRequestID += 1
                Haptics.tap()
            }
            .accessibilityLabel("路线聚焦")

            MapControlButton(icon: "location.fill",
                             selected: cameraMode != .route) {
                onLocateTapped?()
                cameraMode = LocationFocusCycle.next(after: cameraMode)
                cameraRequestID += 1
                Haptics.tap()
            }
            .accessibilityLabel("定位:概览与跟随循环切换")
        }
    }
}

/// 圆形地图控制按钮(与行中页原样式一致)。
struct MapControlButton: View {
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? WDColor.onDark : WDColor.ricePaper)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(selected ? WDColor.ink : WDColor.deepMoss.opacity(0.96))
                        .overlay(Circle().stroke(WDColor.line.opacity(selected ? 0 : 0.8), lineWidth: 1))
                        .shadow(color: WDColor.ink.opacity(0.12), radius: 8, y: 4)
                )
        }
        .buttonStyle(.plain)
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
