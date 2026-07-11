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
        if let currentCoordinate,
           let horizontalAccuracyMeters,
           horizontalAccuracyMeters.isFinite,
           horizontalAccuracyMeters > 0 {
            map.addOverlay(MKCircle(center: currentCoordinate,
                                    radius: min(horizontalAccuracyMeters, 500)))
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

        updateCamera(map, polyline: polyline, coordinator: context.coordinator, fitRoute: fitRoute)
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

    final class Coordinator: NSObject, MKMapViewDelegate {
        var isOffRoute = false
        var lastCameraMode: RouteMapCameraMode?
        var lastCameraRequestID: Int?

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
