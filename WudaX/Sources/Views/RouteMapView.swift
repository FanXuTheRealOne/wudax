import SwiftUI
import MapKit

/// 本地 GPX 轨迹叠加层。底图是否可用由系统缓存决定，不能把在线瓦片假装成离线资源。
struct RouteMapView: UIViewRepresentable {
    let points: [GPXTrackPoint]
    var currentCoordinate: CLLocationCoordinate2D?

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
        update(map, fitRoute: map.overlays.isEmpty)
    }

    private func update(_ map: MKMapView, fitRoute: Bool) {
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }
        map.removeOverlays(map.overlays)
        map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
        if let currentCoordinate {
            map.setCenter(currentCoordinate, animated: true)
        } else if fitRoute {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            map.setVisibleMapRect(polyline.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
                                  animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(WDColor.bamboo)
            renderer.lineWidth = 4
            renderer.lineJoin = .round
            return renderer
        }
    }
}
