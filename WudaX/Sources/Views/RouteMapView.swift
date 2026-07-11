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
    /// 在路线起终点画旗标(行中大地图用)。
    var showsEndpointFlags = false
    /// 尚未到达起点:从当前位置到路线起点画虚线引导。
    var guideLineToStart = false

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
        update(map, context: context, fitRoute: true)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.isOffRoute = isOffRoute
        update(map, context: context, fitRoute: map.overlays.isEmpty)
    }

    private func update(_ map: MKMapView, context: Context, fitRoute: Bool) {
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)
        var guidePolyline: GuidePolyline?
        if guideLineToStart, let currentCoordinate, let start = coordinates.first {
            var guide = [currentCoordinate, start]
            let overlay = GuidePolyline(coordinates: &guide, count: 2)
            guidePolyline = overlay
            map.addOverlay(overlay)
        }
        if let currentCoordinate,
           let horizontalAccuracyMeters,
           horizontalAccuracyMeters.isFinite,
           horizontalAccuracyMeters > 0 {
            map.addOverlay(MKCircle(center: currentCoordinate,
                                    radius: min(horizontalAccuracyMeters, 500)))
        }
        if showsEndpointFlags, let start = coordinates.first, let end = coordinates.last {
            map.addAnnotation(EndpointAnnotation(coordinate: start, isStart: true))
            let separation = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            // 环线起终点重合时只画起点旗。
            if separation > 30 {
                map.addAnnotation(EndpointAnnotation(coordinate: end, isStart: false))
            }
        }
        if let matchedCoordinate {
            map.addAnnotation(MatchedRouteAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: matchedCoordinate.latitude,
                                                   longitude: matchedCoordinate.longitude),
                confidence: matchConfidence,
                isOffRoute: isOffRoute
            ))
        }
        if let currentCoordinate {
            map.addAnnotation(UserNavigationAnnotation(
                coordinate: currentCoordinate,
                headingDegrees: userHeadingDegrees
            ))
        }

        updateCamera(map, polyline: polyline, guidePolyline: guidePolyline,
                     coordinator: context.coordinator, fitRoute: fitRoute)
    }

    private func updateCamera(_ map: MKMapView,
                              polyline: MKPolyline,
                              guidePolyline: GuidePolyline?,
                              coordinator: Coordinator,
                              fitRoute: Bool) {
        switch cameraMode {
        case .automatic:
            if let currentCoordinate {
                if let guidePolyline {
                    // 前往起点阶段:始终保持自己与起点旗标(虚线两端)同屏。
                    map.setRegion(paddedRegion(for: guidePolyline.boundingMapRect, scale: 1.8,
                                               minDelta: 0.008),
                                  animated: coordinator.hasSetUserRegion)
                    coordinator.hasSetUserRegion = true
                } else if coordinator.hasSetUserRegion {
                    map.setCenter(currentCoordinate, animated: true)
                } else {
                    map.setRegion(MKCoordinateRegion(center: currentCoordinate,
                                                     latitudinalMeters: 1_500,
                                                     longitudinalMeters: 1_500),
                                  animated: false)
                    coordinator.hasSetUserRegion = true
                }
            } else if !coordinator.hasSetInitialRegion {
                // 尚无定位:先展示整条路线。setRegion 在布局完成前调用也能正确生效,
                // 带 edgePadding 的 setVisibleMapRect 在零尺寸地图上会退化成全球视野。
                map.setRegion(paddedRegion(for: polyline.boundingMapRect, scale: 1.25), animated: false)
            }
            coordinator.hasSetInitialRegion = true

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
            guard needsFocus, let currentCoordinate else { return }
            map.setRegion(
                MKCoordinateRegion(center: currentCoordinate,
                                   latitudinalMeters: 1_200,
                                   longitudinalMeters: 1_200),
                animated: true
            )
            coordinator.hasSetInitialRegion = true
            coordinator.hasSetUserRegion = true
            coordinator.lastCameraMode = cameraMode
            coordinator.lastCameraRequestID = cameraRequestID
        }
    }

    /// 由 boundingMapRect 计算带边距的 region,避免依赖地图已布局的 edgePadding fit。
    private func paddedRegion(for rect: MKMapRect, scale: Double, minDelta: Double = 0) -> MKCoordinateRegion {
        var region = MKCoordinateRegion(rect)
        region.span.latitudeDelta = min(max(region.span.latitudeDelta * scale, minDelta), 160)
        region.span.longitudeDelta = min(max(region.span.longitudeDelta * scale, minDelta), 340)
        return region
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var isOffRoute = false
        var lastCameraMode: RouteMapCameraMode?
        var lastCameraRequestID: Int?
        var hasSetInitialRegion = false
        var hasSetUserRegion = false

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
            if let annotation = annotation as? EndpointAnnotation {
                let identifier = annotation.isStart ? "route-start-flag" : "route-end-flag"
                let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                marker.annotation = annotation
                marker.canShowCallout = false
                marker.glyphImage = UIImage(systemName: annotation.isStart ? "flag.fill" : "flag.checkered")
                marker.markerTintColor = annotation.isStart ? UIColor(WDColor.bamboo) : UIColor(WDColor.ink)
                marker.displayPriority = .required
                return marker
            }

            if let annotation = annotation as? UserNavigationAnnotation {
                let identifier = "user-navigation-position"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKAnnotationView)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.canShowCallout = false
                let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
                view.image = UIImage(systemName: "location.north.fill", withConfiguration: configuration)?
                    .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
                let heading = annotation.headingDegrees ?? 0
                view.transform = CGAffineTransform(rotationAngle: CGFloat(heading * .pi / 180))
                return view
            }

            guard let annotation = annotation as? MatchedRouteAnnotation else { return nil }
            let identifier = "matched-route-position"
            let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            marker.annotation = annotation
            marker.canShowCallout = true
            marker.glyphImage = UIImage(systemName: annotation.confidence == RouteMatchConfidence.none
                                        ? "questionmark" : "figure.hiking")
            marker.markerTintColor = annotation.isOffRoute ? .systemRed
                : annotation.confidence == .low ? .systemOrange
                : UIColor(WDColor.bamboo)
            return marker
        }
    }
}

/// 用户当前位置 → 路线起点的虚线引导(区别于主路线实线)。
private final class GuidePolyline: MKPolyline {}

/// 路线起点 / 终点旗标。
private final class EndpointAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let isStart: Bool
    var title: String? { isStart ? "起点" : "终点" }

    init(coordinate: CLLocationCoordinate2D, isStart: Bool) {
        self.coordinate = coordinate
        self.isStart = isStart
    }
}

private final class MatchedRouteAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let confidence: RouteMatchConfidence?
    let isOffRoute: Bool
    var title: String? { isOffRoute ? "可能偏离路线" : "路线匹配位置" }

    init(coordinate: CLLocationCoordinate2D, confidence: RouteMatchConfidence?, isOffRoute: Bool) {
        self.coordinate = coordinate
        self.confidence = confidence
        self.isOffRoute = isOffRoute
    }
}

private final class UserNavigationAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let headingDegrees: CLLocationDirection?

    init(coordinate: CLLocationCoordinate2D, headingDegrees: CLLocationDirection?) {
        self.coordinate = coordinate
        self.headingDegrees = headingDegrees
    }
}
