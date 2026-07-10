import Foundation

final class GPXRouteMatcher {
    private struct GridKey: Hashable {
        var x: Int
        var y: Int
    }

    private struct LocalPoint {
        var x: Double
        var y: Double
    }

    private struct Candidate {
        var segment: PreparedRouteSegment
        var fraction: Double
        var localPoint: LocalPoint
        var distanceMeters: Double
        var progressMeters: Double
        var elevationMeters: Double?
        var headingDifference: Double?
        var score: Double
        var isPhysicallyPlausible: Bool
    }

    private struct ReliableState {
        var progressMeters: Double
        var coordinate: RouteCoordinate
        var timestamp: Date
        var speedMetersPerSecond: Double
        var horizontalAccuracyMeters: Double
    }

    let route: PreparedGPXRoute

    private let gridCellSizeMeters = 200.0
    private var spatialGrid: [GridKey: [Int]] = [:]
    private var lastReliable: ReliableState?
    private var lastResult: RouteMatchResult?
    private var consecutiveOffRouteEvidence = 0
    private var consecutiveOnRouteEvidence = 0
    private var offRouteLatched = false

    init(route: PreparedGPXRoute) {
        self.route = route
        buildSpatialGrid()
    }

    func reset() {
        lastReliable = nil
        lastResult = nil
        consecutiveOffRouteEvidence = 0
        consecutiveOnRouteEvidence = 0
        offRouteLatched = false
    }

    func match(_ input: RouteLocationInput) -> RouteMatchResult {
        let accuracy = normalizedAccuracy(input.horizontalAccuracyMeters)
        let localInput = localPoint(for: input.coordinate)
        let candidateSegmentIndices = nearbySegmentIndices(to: localInput, accuracy: accuracy)
        var candidates = candidateSegmentIndices.map {
            scoreCandidate(segment: route.segments[$0], input: input,
                           localInput: localInput, accuracy: accuracy)
        }
        candidates.sort { $0.score < $1.score }

        guard let best = candidates.first else {
            return locationUnavailable(at: input.timestamp,
                                       cadenceStepsPerMinute: input.cadenceStepsPerMinute)
        }

        let ambiguous = candidates.dropFirst().first.map {
            abs($0.score - best.score) < 9 && abs($0.progressMeters - best.progressMeters) > 45
        } ?? false
        updateOffRouteState(candidate: best, accuracy: accuracy)
        var confidence = confidence(for: best, input: input, accuracy: accuracy, ambiguous: ambiguous)
        if offRouteLatched && confidence == .high { confidence = .medium }

        let matchedCoordinate = coordinate(for: best.localPoint)
        let isReliable = (confidence == .high || confidence == .medium) &&
            best.isPhysicallyPlausible && !offRouteLatched
        let effectiveSpeed = Self.effectiveSpeed(input)
        if isReliable {
            lastReliable = ReliableState(progressMeters: best.progressMeters,
                                         coordinate: matchedCoordinate,
                                         timestamp: input.timestamp,
                                         speedMetersPerSecond: effectiveSpeed,
                                         horizontalAccuracyMeters: accuracy)
        }

        let lastReliableProgress = lastReliable?.progressMeters ?? 0
        let waypoint = nextWaypoint(after: best.progressMeters)
        let result = RouteMatchResult(
            routeProgressMeters: best.progressMeters,
            matchedCoordinate: matchedCoordinate,
            distanceToRouteMeters: best.distanceMeters,
            remainingDistanceMeters: max(0, route.totalDistanceMeters - best.progressMeters),
            remainingAscentMeters: remainingAscent(on: best.segment, fraction: best.fraction),
            nextWaypoint: waypoint,
            distanceToNextWaypointMeters: waypoint.map { max(0, $0.routeProgressMeters - best.progressMeters) },
            confidence: confidence,
            isOffRoute: offRouteLatched,
            offRouteConfidence: offRouteConfidence(candidate: best, accuracy: accuracy),
            lastReliableProgressMeters: lastReliableProgress,
            locationSource: .gpsMatched,
            progressRangeStartMeters: nil,
            progressRangeEndMeters: nil,
            reason: reason(for: best, confidence: confidence, ambiguous: ambiguous, accuracy: accuracy)
        )
        lastResult = result
        return result
    }

    func locationUnavailable(at timestamp: Date,
                             cadenceStepsPerMinute: Double?) -> RouteMatchResult {
        guard let reliable = lastReliable else {
            let start = location(at: 0)
            let result = makeUnavailableResult(progress: 0, location: start,
                                               reason: "尚无可信 GPS 路线位置")
            lastResult = result
            return result
        }

        let elapsed = max(0, timestamp.timeIntervalSince(reliable.timestamp))
        guard elapsed <= 120 else {
            let location = location(at: reliable.progressMeters)
            let result = makeUnavailableResult(progress: reliable.progressMeters, location: location,
                                               reason: "GPS 已长时间无有效更新，显示最后可信位置")
            lastResult = result
            return result
        }

        let cadenceSpeed = cadenceStepsPerMinute.map { min(max($0, 0), 220) * 0.72 / 60 }
        let estimatedSpeed = min(max(cadenceSpeed ?? reliable.speedMetersPerSecond, 0), 2.4)
        let travelled = min(elapsed * estimatedSpeed, 220)
        let estimatedProgress = min(route.totalDistanceMeters, reliable.progressMeters + travelled)
        let uncertainty = max(20, reliable.horizontalAccuracyMeters + elapsed * 0.8)
        let rangeStart = max(reliable.progressMeters, estimatedProgress - uncertainty)
        let rangeEnd = min(route.totalDistanceMeters, estimatedProgress + uncertainty)
        let location = location(at: estimatedProgress)
        let waypoint = nextWaypoint(after: estimatedProgress)
        let confidence: RouteMatchConfidence = elapsed <= 45 ? .medium : .low
        let result = RouteMatchResult(
            routeProgressMeters: estimatedProgress,
            matchedCoordinate: location.coordinate,
            distanceToRouteMeters: lastResult?.distanceToRouteMeters ?? reliable.horizontalAccuracyMeters,
            remainingDistanceMeters: max(0, route.totalDistanceMeters - estimatedProgress),
            remainingAscentMeters: location.remainingAscentMeters,
            nextWaypoint: waypoint,
            distanceToNextWaypointMeters: waypoint.map { max(0, $0.routeProgressMeters - estimatedProgress) },
            confidence: confidence,
            isOffRoute: offRouteLatched,
            offRouteConfidence: offRouteLatched ? .medium : .none,
            lastReliableProgressMeters: reliable.progressMeters,
            locationSource: .estimated,
            progressRangeStartMeters: rangeStart,
            progressRangeEndMeters: rangeEnd,
            reason: "GPS 短时丢失，按最后可信进度、速度与步频估算路线区间"
        )
        lastResult = result
        return result
    }

    private func buildSpatialGrid() {
        for segment in route.segments {
            let minimumCellX = Int(floor(segment.minimumX / gridCellSizeMeters))
            let maximumCellX = Int(floor(segment.maximumX / gridCellSizeMeters))
            let minimumCellY = Int(floor(segment.minimumY / gridCellSizeMeters))
            let maximumCellY = Int(floor(segment.maximumY / gridCellSizeMeters))
            for x in minimumCellX...maximumCellX {
                for y in minimumCellY...maximumCellY {
                    spatialGrid[GridKey(x: x, y: y), default: []].append(segment.index)
                }
            }
        }
    }

    private func nearbySegmentIndices(to point: LocalPoint, accuracy: Double) -> [Int] {
        let radius = max(120, min(accuracy * 2.5, 500))
        let minimumCellX = Int(floor((point.x - radius) / gridCellSizeMeters))
        let maximumCellX = Int(floor((point.x + radius) / gridCellSizeMeters))
        let minimumCellY = Int(floor((point.y - radius) / gridCellSizeMeters))
        let maximumCellY = Int(floor((point.y + radius) / gridCellSizeMeters))
        var result = Set<Int>()
        for x in minimumCellX...maximumCellX {
            for y in minimumCellY...maximumCellY {
                result.formUnion(spatialGrid[GridKey(x: x, y: y)] ?? [])
            }
        }
        // A far off-route sample may not intersect the nearby grid. Falling
        // back to a full scan preserves a real distance-to-route output.
        return result.isEmpty ? route.segments.map(\.index) : result.sorted()
    }

    private func scoreCandidate(segment: PreparedRouteSegment,
                                input: RouteLocationInput,
                                localInput: LocalPoint,
                                accuracy: Double) -> Candidate {
        let startVertex = route.vertices[segment.startVertexIndex]
        let endVertex = route.vertices[segment.endVertexIndex]
        let start = LocalPoint(x: startVertex.localXMeters, y: startVertex.localYMeters)
        let end = LocalPoint(x: endVertex.localXMeters, y: endVertex.localYMeters)
        let projection = Self.project(point: localInput, start: start, end: end)
        let distance = hypot(localInput.x - projection.point.x, localInput.y - projection.point.y)
        let progress = segment.cumulativeStartMeters + projection.fraction * segment.lengthMeters
        let headingDifference = validCourse(input).map {
            Self.headingDifference($0, segment.bearingDegrees)
        }
        let corridor = max(20, accuracy * 1.4)
        var score = min(distance / corridor, 5) * 34
        if let headingDifference { score += headingDifference / 180 * 32 }

        var isPlausible = true
        if let reliable = lastReliable {
            let elapsed = max(1, input.timestamp.timeIntervalSince(reliable.timestamp))
            let speed = max(Self.effectiveSpeed(input), reliable.speedMetersPerSecond)
            let expectedTravel = speed * elapsed
            let forwardAllowance = max(70, expectedTravel * 3 + accuracy * 2)
            let backwardAllowance = max(45, expectedTravel * 2 + accuracy)
            let delta = progress - reliable.progressMeters
            if delta > forwardAllowance || delta < -backwardAllowance {
                isPlausible = false
                let overflow = delta > 0 ? delta - forwardAllowance : -delta - backwardAllowance
                score += 110 + min(overflow / 5, 120)
            } else {
                score += min(abs(delta - expectedTravel) / max(forwardAllowance, 1), 1) * 16
            }
        }

        let elevation = interpolatedElevation(start: startVertex.elevationMeters,
                                              end: endVertex.elevationMeters,
                                              fraction: projection.fraction)
        if let altitude = input.altitudeMeters, altitude.isFinite, let elevation {
            score += min(abs(altitude - elevation) / 45, 2) * 8
        }
        if headingDifference == nil && segmentIsAmbiguous(segment.index) { score += 7 }

        return Candidate(segment: segment, fraction: projection.fraction,
                         localPoint: projection.point, distanceMeters: distance,
                         progressMeters: progress, elevationMeters: elevation,
                         headingDifference: headingDifference, score: score,
                         isPhysicallyPlausible: isPlausible)
    }

    private func confidence(for candidate: Candidate, input: RouteLocationInput,
                            accuracy: Double, ambiguous: Bool) -> RouteMatchConfidence {
        guard input.horizontalAccuracyMeters >= 0, accuracy <= 250 else { return .none }
        if !candidate.isPhysicallyPlausible { return .low }
        let headingIsStrong = candidate.headingDifference.map { $0 <= 35 } ?? true
        if accuracy <= 20 && candidate.distanceMeters <= max(15, accuracy * 1.25) &&
            headingIsStrong && !ambiguous {
            return .high
        }
        if accuracy <= 70 && candidate.distanceMeters <= max(45, accuracy * 1.6) &&
            candidate.score <= 90 && !ambiguous {
            return .medium
        }
        if candidate.distanceMeters <= max(300, accuracy * 3) { return .low }
        return .none
    }

    private func updateOffRouteState(candidate: Candidate, accuracy: Double) {
        let threshold = max(45, min(accuracy * 1.5, 180))
        let headingConflict = candidate.headingDifference.map { $0 >= 55 } ?? false
        let evidence = candidate.distanceMeters > threshold &&
            (headingConflict || candidate.distanceMeters > threshold * 1.5)
        if evidence {
            consecutiveOffRouteEvidence += 1
            consecutiveOnRouteEvidence = 0
            if consecutiveOffRouteEvidence >= 3 { offRouteLatched = true }
        } else if candidate.distanceMeters <= threshold * 0.65 {
            consecutiveOnRouteEvidence += 1
            consecutiveOffRouteEvidence = max(0, consecutiveOffRouteEvidence - 1)
            if consecutiveOnRouteEvidence >= 2 {
                offRouteLatched = false
                consecutiveOffRouteEvidence = 0
            }
        }
    }

    private func offRouteConfidence(candidate: Candidate, accuracy: Double) -> OffRouteConfidence {
        guard consecutiveOffRouteEvidence > 0 || offRouteLatched else { return .none }
        let threshold = max(45, min(accuracy * 1.5, 180))
        if offRouteLatched && candidate.distanceMeters > threshold * 1.5 { return .high }
        if offRouteLatched { return .medium }
        return .low
    }

    private func reason(for candidate: Candidate, confidence: RouteMatchConfidence,
                        ambiguous: Bool, accuracy: Double) -> String {
        if offRouteLatched {
            return "连续定位显示距计划路线约 \(Int(candidate.distanceMeters.rounded())) 米，且方向或进度与路线不一致"
        }
        if !candidate.isPhysicallyPlausible {
            return "候选路线位置会造成不合理的进度跳跃，已保留历史连续性"
        }
        if ambiguous { return "附近存在多个相似路线段，结合历史进度后仍有歧义" }
        switch confidence {
        case .high: return "GPS 精度良好，距离路线近，方向和进度连续"
        case .medium: return "GPS 有一定漂移，但与路线方向和历史进度一致"
        case .low: return "GPS 精度或路线几何存在歧义，暂不更新最后可信进度"
        case .none: return accuracy > 250 ? "GPS 精度不可用" : "当前位置与路线及历史进度明显冲突"
        }
    }

    private func segmentIsAmbiguous(_ index: Int) -> Bool {
        route.ambiguousSegmentPairs.contains {
            $0.firstSegmentIndex == index || $0.secondSegmentIndex == index
        }
    }

    private func nextWaypoint(after progress: Double) -> PreparedRouteWaypoint? {
        route.waypoints.first { $0.routeProgressMeters > progress + 3 }
    }

    private func remainingAscent(on segment: PreparedRouteSegment, fraction: Double) -> Double {
        let start = route.vertices[segment.startVertexIndex].remainingAscentMeters
        let end = route.vertices[segment.endVertexIndex].remainingAscentMeters
        return max(0, start + (end - start) * fraction)
    }

    private func makeUnavailableResult(progress: Double,
                                       location: (coordinate: RouteCoordinate, remainingAscentMeters: Double),
                                       reason: String) -> RouteMatchResult {
        let waypoint = nextWaypoint(after: progress)
        return RouteMatchResult(
            routeProgressMeters: progress,
            matchedCoordinate: location.coordinate,
            distanceToRouteMeters: lastResult?.distanceToRouteMeters ?? 0,
            remainingDistanceMeters: max(0, route.totalDistanceMeters - progress),
            remainingAscentMeters: location.remainingAscentMeters,
            nextWaypoint: waypoint,
            distanceToNextWaypointMeters: waypoint.map { max(0, $0.routeProgressMeters - progress) },
            confidence: .none,
            isOffRoute: offRouteLatched,
            offRouteConfidence: offRouteLatched ? .medium : .none,
            lastReliableProgressMeters: lastReliable?.progressMeters ?? progress,
            locationSource: .lastKnown,
            progressRangeStartMeters: nil,
            progressRangeEndMeters: nil,
            reason: reason
        )
    }

    private func location(at progress: Double) -> (coordinate: RouteCoordinate, remainingAscentMeters: Double) {
        let clamped = min(max(progress, 0), route.totalDistanceMeters)
        let segment = route.segments.first {
            clamped >= $0.cumulativeStartMeters && clamped <= $0.cumulativeEndMeters
        } ?? route.segments[route.segments.count - 1]
        let fraction = segment.lengthMeters > 0
            ? min(max((clamped - segment.cumulativeStartMeters) / segment.lengthMeters, 0), 1)
            : 0
        let start = route.vertices[segment.startVertexIndex]
        let end = route.vertices[segment.endVertexIndex]
        let point = LocalPoint(x: start.localXMeters + (end.localXMeters - start.localXMeters) * fraction,
                               y: start.localYMeters + (end.localYMeters - start.localYMeters) * fraction)
        return (coordinate(for: point), remainingAscent(on: segment, fraction: fraction))
    }

    private func localPoint(for coordinate: RouteCoordinate) -> LocalPoint {
        let radians = Double.pi / 180
        return LocalPoint(
            x: (coordinate.longitude - route.origin.longitude) * radians * 6_371_000 * cos(route.origin.latitude * radians),
            y: (coordinate.latitude - route.origin.latitude) * radians * 6_371_000
        )
    }

    private func coordinate(for point: LocalPoint) -> RouteCoordinate {
        let radians = Double.pi / 180
        return RouteCoordinate(
            latitude: route.origin.latitude + point.y / 6_371_000 / radians,
            longitude: route.origin.longitude + point.x / (6_371_000 * cos(route.origin.latitude * radians)) / radians
        )
    }

    private func normalizedAccuracy(_ accuracy: Double) -> Double {
        accuracy.isFinite && accuracy >= 0 ? max(accuracy, 3) : 1_000
    }

    private func validCourse(_ input: RouteLocationInput) -> Double? {
        guard let course = input.courseDegrees, course.isFinite, course >= 0,
              Self.effectiveSpeed(input) >= 0.6 else { return nil }
        return Self.normalizedDegrees(course)
    }

    private func interpolatedElevation(start: Double?, end: Double?, fraction: Double) -> Double? {
        guard let start, let end, start.isFinite, end.isFinite else { return nil }
        return start + (end - start) * fraction
    }

    private static func effectiveSpeed(_ input: RouteLocationInput) -> Double {
        if let speed = input.speedMetersPerSecond, speed.isFinite, speed >= 0 { return min(speed, 8) }
        if let cadence = input.cadenceStepsPerMinute, cadence.isFinite, cadence >= 0 {
            return min(cadence, 220) * 0.72 / 60
        }
        return 1.0
    }

    private static func project(point: LocalPoint, start: LocalPoint,
                                end: LocalPoint) -> (point: LocalPoint, fraction: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (start, 0) }
        let fraction = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        return (LocalPoint(x: start.x + fraction * dx, y: start.y + fraction * dy), fraction)
    }

    private static func headingDifference(_ first: Double, _ second: Double) -> Double {
        let raw = abs(normalizedDegrees(first) - normalizedDegrees(second))
        return min(raw, 360 - raw)
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}
