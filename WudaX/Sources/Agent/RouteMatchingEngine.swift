import CoreLocation
import Foundation

// MARK: - GPX route geometry

struct RouteCoordinate: Hashable {
    let latitude: Double
    let longitude: Double
    let elevation: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RouteWaypoint: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: RouteCoordinate
    let routeDistanceMeters: CLLocationDistance
}

struct RouteGeometry {
    let points: [RouteCoordinate]
    let cumulativeDistanceMeters: [CLLocationDistance]
    let remainingAscentMeters: [CLLocationDistance]
    let waypoints: [RouteWaypoint]

    init(points: [RouteCoordinate], waypoints: [RouteWaypoint] = []) {
        self.points = points
        self.waypoints = waypoints

        var distances: [CLLocationDistance] = [0]
        if points.count > 1 {
            for index in 1..<points.count {
                let a = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
                let b = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
                distances.append(distances[index - 1] + a.distance(from: b))
            }
        }
        cumulativeDistanceMeters = distances

        var ascent = Array(repeating: CLLocationDistance(0), count: points.count)
        if points.count > 1 {
            for index in stride(from: points.count - 2, through: 0, by: -1) {
                ascent[index] = ascent[index + 1] + max(0, points[index + 1].elevation - points[index].elevation)
            }
        }
        remainingAscentMeters = ascent
    }

    var totalDistanceMeters: CLLocationDistance { cumulativeDistanceMeters.last ?? 0 }
    var totalAscentMeters: CLLocationDistance { remainingAscentMeters.first ?? 0 }

    func profile(sampleCount: Int = 72) -> [Double] {
        guard points.count > sampleCount, sampleCount > 1 else { return points.map(\.elevation) }
        return (0..<sampleCount).map { position in
            points[Int(Double(position) / Double(sampleCount - 1) * Double(points.count - 1))].elevation
        }
    }
}

enum RouteMatchConfidence: String {
    case high, medium, low, none

    var displayName: String {
        switch self {
        case .high: return "定位可靠"
        case .medium: return "估算位置"
        case .low: return "定位不稳定"
        case .none: return "无法确认位置"
        }
    }
}

enum RouteMatchSource: String { case gpsMatched, estimated, lastKnown }

struct RouteMatch {
    let routeProgressMeters: CLLocationDistance
    let matchedCoordinate: CLLocationCoordinate2D?
    let distanceToRouteMeters: CLLocationDistance?
    let remainingDistanceMeters: CLLocationDistance
    let remainingAscentMeters: CLLocationDistance
    let nextWaypoint: RouteWaypoint?
    let distanceToNextWaypointMeters: CLLocationDistance?
    let confidence: RouteMatchConfidence
    let isOffRoute: Bool
    let lastReliableProgressMeters: CLLocationDistance?
    let locationSource: RouteMatchSource
    let reason: String
}

/// Offline, route-constrained matcher. It only searches the imported GPX line;
/// no online road graph or map-matching service is required.
final class RouteMatchingEngine {
    private struct Segment {
        let index: Int
        let start: RouteCoordinate
        let end: RouteCoordinate
        let startDistance: CLLocationDistance
        let length: CLLocationDistance
        let bearing: CLLocationDirection
    }

    private struct GridCell: Hashable { let latitude: Int; let longitude: Int }
    private struct Projection { let coordinate: CLLocationCoordinate2D; let fraction: Double; let distance: CLLocationDistance; let elevation: Double }
    private struct Candidate { let segment: Segment; let projection: Projection; let progress: CLLocationDistance; let score: Double }

    private let route: RouteGeometry
    private let segments: [Segment]
    private let grid: [GridCell: [Int]]
    private let cellSize = 0.001
    private var lastReliable: (progress: CLLocationDistance, segment: Int, date: Date)?
    private var routeDirection = 1.0
    private var offRouteReadings = 0

    init(route: RouteGeometry) {
        self.route = route
        var built: [Segment] = []
        if route.points.count > 1 {
            for index in 0..<(route.points.count - 1) {
                let start = route.points[index]
                let end = route.points[index + 1]
                let length = CLLocation(latitude: start.latitude, longitude: start.longitude)
                    .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
                guard length > 0.5 else { continue }
                built.append(.init(index: index, start: start, end: end, startDistance: route.cumulativeDistanceMeters[index], length: length, bearing: Self.bearing(from: start.coordinate, to: end.coordinate)))
            }
        }
        segments = built

        var index: [GridCell: [Int]] = [:]
        for segmentIndex in built.indices {
            let segment = built[segmentIndex]
            let minLat = Int(floor(min(segment.start.latitude, segment.end.latitude) / cellSize))
            let maxLat = Int(floor(max(segment.start.latitude, segment.end.latitude) / cellSize))
            let minLon = Int(floor(min(segment.start.longitude, segment.end.longitude) / cellSize))
            let maxLon = Int(floor(max(segment.start.longitude, segment.end.longitude) / cellSize))
            for lat in minLat...maxLat {
                for lon in minLon...maxLon {
                    index[GridCell(latitude: lat, longitude: lon), default: []].append(segmentIndex)
                }
            }
        }
        grid = index
    }

    func match(location: CLLocation) -> RouteMatch {
        guard !segments.isEmpty else { return unavailable("路线没有可匹配的线段") }
        let accuracy = location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 65
        let radius = max(45, min(180, accuracy * 2))
        let candidates = nearbySegments(location.coordinate, radius: radius).compactMap { segmentIndex -> Candidate? in
            guard segments.indices.contains(segmentIndex) else { return nil }
            let segment = segments[segmentIndex]
            let projection = project(location.coordinate, onto: segment)
            let progress = segment.startDistance + segment.length * projection.fraction
            return Candidate(segment: segment, projection: projection, progress: progress, score: candidateScore(projection: projection, progress: progress, segment: segment, location: location, radius: radius, accuracy: accuracy))
        }.sorted { $0.score < $1.score }

        guard let best = candidates.first else {
            offRouteReadings += 1
            return estimateOrUnavailable(location, reason: "周围没有可匹配的路线段")
        }

        let confidence = confidence(for: best, accuracy: accuracy, radius: radius)
        let likelyOffRoute = best.projection.distance > max(35, accuracy * 1.6)
        offRouteReadings = likelyOffRoute ? offRouteReadings + 1 : 0
        if confidence == .high || confidence == .medium { updateReliable(best, location: location) }

        let waypoint = route.waypoints.filter { $0.routeDistanceMeters >= best.progress - 10 }.min { $0.routeDistanceMeters < $1.routeDistanceMeters }
        return RouteMatch(
            routeProgressMeters: best.progress,
            matchedCoordinate: best.projection.coordinate,
            distanceToRouteMeters: best.projection.distance,
            remainingDistanceMeters: max(0, route.totalDistanceMeters - best.progress),
            remainingAscentMeters: remainingAscent(segment: best.segment.index, fraction: best.projection.fraction),
            nextWaypoint: waypoint,
            distanceToNextWaypointMeters: waypoint.map { max(0, $0.routeDistanceMeters - best.progress) },
            confidence: confidence,
            isOffRoute: offRouteReadings >= 3,
            lastReliableProgressMeters: lastReliable?.progress,
            locationSource: confidence == .low ? .lastKnown : .gpsMatched,
            reason: reason(confidence: confidence, isOffRoute: offRouteReadings >= 3, distance: best.projection.distance)
        )
    }

    private func nearbySegments(_ coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) -> [Int] {
        let center = cell(for: coordinate)
        let cells = max(1, Int(ceil(radius / (111_000 * cellSize))))
        var result = Set<Int>()
        for lat in (center.latitude - cells)...(center.latitude + cells) {
            for lon in (center.longitude - cells)...(center.longitude + cells) {
                result.formUnion(grid[GridCell(latitude: lat, longitude: lon)] ?? [])
            }
        }
        return Array(result)
    }

    private func candidateScore(projection: Projection, progress: CLLocationDistance, segment: Segment, location: CLLocation, radius: CLLocationDistance, accuracy: CLLocationAccuracy) -> Double {
        var score = projection.distance / radius
        if location.course >= 0, location.speed > 0.45 {
            score += min(1.2, angularDifference(location.course, segment.bearing) / 90) * 0.8
        }
        if location.verticalAccuracy >= 0, projection.elevation != 0 {
            score += min(0.6, abs(location.altitude - projection.elevation) / 80) * 0.3
        }
        if let previous = lastReliable {
            let elapsed = max(0, location.timestamp.timeIntervalSince(previous.date))
            let speed = location.speed > 0.35 ? min(location.speed, 4) : 1.4
            let allowed = max(60, speed * elapsed * 3 + accuracy * 2)
            let jump = abs(progress - previous.progress)
            if jump > allowed { score += min(6, (jump - allowed) / allowed * 2.4) }
        }
        return score
    }

    private func confidence(for candidate: Candidate, accuracy: CLLocationAccuracy, radius: CLLocationDistance) -> RouteMatchConfidence {
        if candidate.projection.distance <= max(12, accuracy * 0.85), candidate.score < 1.05 { return .high }
        if candidate.projection.distance <= radius, candidate.score < 2.1 { return .medium }
        if candidate.projection.distance <= radius * 1.5 { return .low }
        return .none
    }

    private func estimateOrUnavailable(_ location: CLLocation, reason: String) -> RouteMatch {
        guard let previous = lastReliable else { return unavailable(reason) }
        let elapsed = location.timestamp.timeIntervalSince(previous.date)
        guard elapsed > 0, elapsed <= 90 else { return unavailable(reason) }
        let speed = location.speed > 0.35 ? min(location.speed, 3) : 0
        let progress = min(route.totalDistanceMeters, max(0, previous.progress + speed * elapsed * routeDirection))
        let segmentIndex = closestSegment(to: progress) ?? previous.segment
        return RouteMatch(routeProgressMeters: progress, matchedCoordinate: coordinate(on: segmentIndex, progress: progress), distanceToRouteMeters: nil, remainingDistanceMeters: max(0, route.totalDistanceMeters - progress), remainingAscentMeters: remainingAscent(segment: segmentIndex, fraction: 0), nextWaypoint: nil, distanceToNextWaypointMeters: nil, confidence: .low, isOffRoute: offRouteReadings >= 3, lastReliableProgressMeters: previous.progress, locationSource: .estimated, reason: "\(reason)，显示基于最后可信位置的短时估算")
    }

    private func unavailable(_ reason: String) -> RouteMatch {
        let progress = lastReliable?.progress ?? 0
        return RouteMatch(routeProgressMeters: progress, matchedCoordinate: nil, distanceToRouteMeters: nil, remainingDistanceMeters: max(0, route.totalDistanceMeters - progress), remainingAscentMeters: 0, nextWaypoint: nil, distanceToNextWaypointMeters: nil, confidence: .none, isOffRoute: offRouteReadings >= 3, lastReliableProgressMeters: lastReliable?.progress, locationSource: .lastKnown, reason: reason)
    }

    private func updateReliable(_ candidate: Candidate, location: CLLocation) {
        if let previous = lastReliable, abs(candidate.progress - previous.progress) > 3 {
            routeDirection = candidate.progress >= previous.progress ? 1 : -1
        } else if location.course >= 0, location.speed > 0.45 {
            routeDirection = angularDifference(location.course, candidate.segment.bearing) > 90 ? -1 : 1
        }
        lastReliable = (candidate.progress, candidate.segment.index, location.timestamp)
    }

    private func remainingAscent(segment: Int, fraction: Double) -> CLLocationDistance {
        guard route.points.indices.contains(segment), route.points.indices.contains(segment + 1) else { return 0 }
        let start = route.points[segment]
        let end = route.points[segment + 1]
        let elevation = start.elevation + (end.elevation - start.elevation) * fraction
        return max(0, end.elevation - elevation) + route.remainingAscentMeters[segment + 1]
    }

    private func closestSegment(to progress: CLLocationDistance) -> Int? {
        segments.min { abs($0.startDistance - progress) < abs($1.startDistance - progress) }?.index
    }

    private func coordinate(on segmentIndex: Int, progress: CLLocationDistance) -> CLLocationCoordinate2D? {
        guard let segment = segments.first(where: { $0.index == segmentIndex }) else { return nil }
        let fraction = min(1, max(0, (progress - segment.startDistance) / segment.length))
        return CLLocationCoordinate2D(latitude: segment.start.latitude + (segment.end.latitude - segment.start.latitude) * fraction, longitude: segment.start.longitude + (segment.end.longitude - segment.start.longitude) * fraction)
    }

    private func project(_ coordinate: CLLocationCoordinate2D, onto segment: Segment) -> Projection {
        let refLatitude = (coordinate.latitude + segment.start.latitude + segment.end.latitude) / 3 * .pi / 180
        let metersPerLongitude = 111_320.0 * cos(refLatitude)
        let vx = (segment.end.longitude - segment.start.longitude) * metersPerLongitude
        let vy = (segment.end.latitude - segment.start.latitude) * 111_132.0
        let wx = (coordinate.longitude - segment.start.longitude) * metersPerLongitude
        let wy = (coordinate.latitude - segment.start.latitude) * 111_132.0
        let denominator = vx * vx + vy * vy
        let fraction = denominator > 0 ? min(1, max(0, (wx * vx + wy * vy) / denominator)) : 0
        let projected = CLLocationCoordinate2D(latitude: segment.start.latitude + (segment.end.latitude - segment.start.latitude) * fraction, longitude: segment.start.longitude + (segment.end.longitude - segment.start.longitude) * fraction)
        return Projection(coordinate: projected, fraction: fraction, distance: hypot(wx - vx * fraction, wy - vy * fraction), elevation: segment.start.elevation + (segment.end.elevation - segment.start.elevation) * fraction)
    }

    private func cell(for coordinate: CLLocationCoordinate2D) -> GridCell {
        GridCell(latitude: Int(floor(coordinate.latitude / cellSize)), longitude: Int(floor(coordinate.longitude / cellSize)))
    }

    private func reason(confidence: RouteMatchConfidence, isOffRoute: Bool, distance: CLLocationDistance) -> String {
        if isOffRoute { return "连续定位点偏离计划路线约 \(Int(distance)) m" }
        switch confidence {
        case .high: return "GPS 精度、路线距离和行进方向一致"
        case .medium: return "位置存在漂移，已结合路线进度和方向修正"
        case .low: return "路线附近存在多个候选位置，请在下一个路标确认"
        case .none: return "当前定位与计划路线无法可靠匹配"
        }
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let latitude1 = start.latitude * .pi / 180
        let latitude2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func angularDifference(_ first: CLLocationDirection, _ second: CLLocationDirection) -> CLLocationDirection {
        let difference = abs((first - second).truncatingRemainder(dividingBy: 360))
        return min(difference, 360 - difference)
    }
}
