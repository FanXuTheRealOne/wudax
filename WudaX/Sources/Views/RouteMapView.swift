import SwiftUI
import MapKit

/// 本地 GPX 轨迹叠加层。底图是否可用由系统缓存决定，不能把在线瓦片假装成离线资源。
struct RouteMapView: UIViewRepresentable {
    let points: [GPXTrackPoint]
    var currentCoordinate: CLLocationCoordinate2D?
    var matchedCoordinate: RouteCoordinate?
    var horizontalAccuracyMeters: Double?
    var matchConfidence: RouteMatchConfidence?
    var isOffRoute = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .standard
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        update(map, fitRoute: true)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.isOffRoute = isOffRoute
        update(map, fitRoute: map.overlays.isEmpty)
    }

    private func update(_ map: MKMapView, fitRoute: Bool) {
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
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
            map.setCenter(currentCoordinate, animated: true)
        } else if fitRoute {
            map.setVisibleMapRect(polyline.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
                                  animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var isOffRoute = false

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
