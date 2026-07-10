import CoreLocation
import Foundation

struct GPXImportResult {
    let route: Route
    let pointCount: Int
    let waypointCount: Int
    let warnings: [String]
}

enum GPXRouteImportError: LocalizedError {
    case unreadableFile, malformedFile, noTrackPoints

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "无法读取 GPX 文件"
        case .malformedFile: return "GPX 文件格式无效"
        case .noTrackPoints: return "GPX 中没有足够的路线点"
        }
    }
}

/// Supports normal GPX tracks/routes and common two-step-route extension statistics.
final class GPXRouteImporter: NSObject, XMLParserDelegate {
    private struct RawPoint {
        let latitude: Double
        let longitude: Double
        var elevation: Double = 0
        var name: String?
    }

    private var trackPoints: [RawPoint] = []
    private var rawWaypoints: [RawPoint] = []
    private var activeTrackPoint: RawPoint?
    private var activeWaypoint: RawPoint?
    private var currentText = ""
    private var extensionValues: [String: String] = [:]

    func load(from url: URL) throws -> GPXImportResult {
        reset()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let parser = XMLParser(contentsOf: url) else { throw GPXRouteImportError.unreadableFile }
        parser.delegate = self
        guard parser.parse() else { throw GPXRouteImportError.malformedFile }
        guard trackPoints.count >= 2 else { throw GPXRouteImportError.noTrackPoints }

        let points = trackPoints.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, elevation: $0.elevation) }
        let baseGeometry = RouteGeometry(points: points)
        let waypoints = rawWaypoints.map { waypoint in
            RouteWaypoint(
                name: waypoint.name?.isEmpty == false ? waypoint.name! : "航点",
                coordinate: RouteCoordinate(latitude: waypoint.latitude, longitude: waypoint.longitude, elevation: waypoint.elevation),
                routeDistanceMeters: closestRouteDistance(for: waypoint, geometry: baseGeometry)
            )
        }
        let geometry = RouteGeometry(points: points, waypoints: waypoints)
        let recordedDistance = decimal("Distance")
        let recordedAscent = decimal("ElevationGain")
        let recordedDescent = decimal("ElevationLoss")
        let distance = geometry.totalDistanceMeters
        let ascent = recordedAscent > 0 ? recordedAscent : geometry.totalAscentMeters
        let descent = recordedDescent > 0 ? recordedDescent : calculatedDescent(points)
        let estimatedHours = max(1, distance / 1_000 / 3.5 + ascent / 600)
        let isOutAndBack = CLLocation(latitude: points[0].latitude, longitude: points[0].longitude)
            .distance(from: CLLocation(latitude: points.last!.latitude, longitude: points.last!.longitude)) < 180

        var warnings: [String] = []
        if rawWaypoints.isEmpty { warnings.append("GPX 未包含命名航点；补水点和撤离点需要用户补充确认") }
        if recordedDistance > 0, abs(recordedDistance - distance) / max(1, distance) > 0.05 {
            warnings.append("文件统计距离与轨迹几何距离差异较大，已按路线几何距离进行定位")
        }

        let route = Route(
            name: extensionValues["name"].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent,
            distanceKm: distance / 1_000,
            ascentM: ascent,
            descentM: descent,
            estimatedHours: estimatedHours,
            elevationProfile: geometry.profile(),
            riskPoints: [],
            hasUnverifiedSegment: true,
            isOutAndBack: isOutAndBack,
            waterSourceCount: 0,
            geometry: geometry
        )
        return GPXImportResult(route: route, pointCount: points.count, waypointCount: waypoints.count, warnings: warnings)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if ["trkpt", "rtept"].contains(elementName), let latitude = Double(attributeDict["lat"] ?? ""), let longitude = Double(attributeDict["lon"] ?? "") {
            activeTrackPoint = RawPoint(latitude: latitude, longitude: longitude)
        } else if elementName == "wpt", let latitude = Double(attributeDict["lat"] ?? ""), let longitude = Double(attributeDict["lon"] ?? "") {
            activeWaypoint = RawPoint(latitude: latitude, longitude: longitude)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "ele", let elevation = Double(value) {
            if activeTrackPoint != nil { activeTrackPoint?.elevation = elevation }
            if activeWaypoint != nil { activeWaypoint?.elevation = elevation }
        } else if elementName == "name" {
            if activeWaypoint != nil { activeWaypoint?.name = value }
            else if !value.isEmpty { extensionValues["name"] = value }
        } else if ["Distance", "ElevationGain", "ElevationLoss", "SportAvgSpeed", "BeginTime", "EndTime"].contains(elementName), !value.isEmpty {
            extensionValues[elementName] = value
        } else if ["trkpt", "rtept"].contains(elementName), let point = activeTrackPoint {
            trackPoints.append(point)
            activeTrackPoint = nil
        } else if elementName == "wpt", let waypoint = activeWaypoint {
            rawWaypoints.append(waypoint)
            activeWaypoint = nil
        }
        currentText = ""
    }

    private func reset() {
        trackPoints = []
        rawWaypoints = []
        activeTrackPoint = nil
        activeWaypoint = nil
        extensionValues = [:]
    }

    private func decimal(_ key: String) -> Double { Double(extensionValues[key] ?? "") ?? 0 }

    private func calculatedDescent(_ points: [RouteCoordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + max(0, $1.0.elevation - $1.1.elevation) }
    }

    private func closestRouteDistance(for waypoint: RawPoint, geometry: RouteGeometry) -> CLLocationDistance {
        let location = CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude)
        guard let closest = geometry.points.enumerated().min(by: {
            location.distance(from: CLLocation(latitude: $0.element.latitude, longitude: $0.element.longitude)) < location.distance(from: CLLocation(latitude: $1.element.latitude, longitude: $1.element.longitude))
        }) else { return 0 }
        return geometry.cumulativeDistanceMeters[closest.offset]
    }
}
