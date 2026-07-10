import Foundation

enum GPXRoutePreparationError: LocalizedError {
    case insufficientPoints

    var errorDescription: String? {
        switch self {
        case .insufficientPoints: "GPX 路线至少需要两个有效且不重复的轨迹点"
        }
    }
}

struct GPXRoutePreprocessor {
    var duplicateThresholdMeters = 1.5
    var simplificationToleranceMeters = 2.5
    var maximumSimplifiedSpacingMeters = 30.0
    var elevationNoiseThresholdMeters = 2.0
    var turnThresholdDegrees = 35.0
    var parallelCorridorMeters = 35.0

    func prepare(_ document: GPXDocument) throws -> PreparedGPXRoute {
        let sourcePointCount = document.points.count
        guard let firstPoint = document.points.first else { throw GPXRoutePreparationError.insufficientPoints }
        let origin = RouteCoordinate(latitude: firstPoint.latitude, longitude: firstPoint.longitude)

        var vertices: [PreparedRouteVertex] = []
        var segments: [PreparedRouteSegment] = []
        var cumulativeDistance = 0.0
        var sourcePointOffset = 0

        for (sourceSegmentIndex, sourceSegment) in document.segments.enumerated() {
            let indexedPoints = sourceSegment.points.enumerated().map { offset, point in
                IndexedPoint(point: point, sourceIndex: sourcePointOffset + offset,
                             local: Self.localPoint(for: point, origin: origin))
            }
            sourcePointOffset += sourceSegment.points.count
            let preparedPoints = simplify(deduplicate(indexedPoints))
            guard preparedPoints.count >= 2 else { continue }

            let segmentStartVertexIndex = vertices.count
            for prepared in preparedPoints {
                vertices.append(PreparedRouteVertex(
                    coordinate: RouteCoordinate(latitude: prepared.point.latitude, longitude: prepared.point.longitude),
                    localXMeters: prepared.local.x,
                    localYMeters: prepared.local.y,
                    elevationMeters: prepared.point.elevationMeters,
                    cumulativeDistanceMeters: cumulativeDistance,
                    remainingDistanceMeters: 0,
                    remainingAscentMeters: 0,
                    sourcePointIndex: prepared.sourceIndex
                ))
            }

            for localIndex in 0..<(preparedPoints.count - 1) {
                let startVertexIndex = segmentStartVertexIndex + localIndex
                let endVertexIndex = startVertexIndex + 1
                let start = vertices[startVertexIndex]
                let end = vertices[endVertexIndex]
                let dx = end.localXMeters - start.localXMeters
                let dy = end.localYMeters - start.localYMeters
                let length = hypot(dx, dy)
                guard length > 0.01 else { continue }
                let elevationDelta = elevationDifference(from: start.elevationMeters, to: end.elevationMeters)
                let ascent = elevationDelta >= elevationNoiseThresholdMeters ? elevationDelta : 0
                let bearing = Self.normalizedDegrees(atan2(dx, dy) * 180 / .pi)
                let routeSegment = PreparedRouteSegment(
                    index: segments.count,
                    sourceSegmentIndex: sourceSegmentIndex,
                    startVertexIndex: startVertexIndex,
                    endVertexIndex: endVertexIndex,
                    lengthMeters: length,
                    cumulativeStartMeters: cumulativeDistance,
                    cumulativeEndMeters: cumulativeDistance + length,
                    bearingDegrees: bearing,
                    gradePercent: elevationDelta.isFinite ? elevationDelta / length * 100 : nil,
                    ascentMeters: ascent,
                    remainingDistanceAtStartMeters: 0,
                    remainingAscentAtStartMeters: 0,
                    minimumX: min(start.localXMeters, end.localXMeters),
                    maximumX: max(start.localXMeters, end.localXMeters),
                    minimumY: min(start.localYMeters, end.localYMeters),
                    maximumY: max(start.localYMeters, end.localYMeters)
                )
                segments.append(routeSegment)
                cumulativeDistance += length
                vertices[endVertexIndex].cumulativeDistanceMeters = cumulativeDistance
            }
        }

        guard vertices.count >= 2, !segments.isEmpty else { throw GPXRoutePreparationError.insufficientPoints }

        let totalAscent = segments.reduce(0) { $0 + $1.ascentMeters }
        applyRemainingMetrics(vertices: &vertices, segments: &segments,
                              totalDistance: cumulativeDistance)
        let turns = findTurns(segments: segments)
        let ambiguousPairs = findAmbiguousPairs(vertices: vertices, segments: segments)
        let isOutAndBack = ambiguousPairs.contains { pair in
            let first = segments[pair.firstSegmentIndex]
            let second = segments[pair.secondSegmentIndex]
            return Self.headingDifference(first.bearingDegrees, second.bearingDegrees) >= 150
        }
        let first = vertices[segments[0].startVertexIndex]
        let last = vertices[segments[segments.count - 1].endVertexIndex]
        let endpointDistance = hypot(last.localXMeters - first.localXMeters,
                                     last.localYMeters - first.localYMeters)
        let isLoop = endpointDistance <= max(60, cumulativeDistance * 0.02)
        let waypoints = document.waypoints.compactMap {
            projectWaypoint($0, origin: origin, vertices: vertices, segments: segments)
        }.sorted { $0.routeProgressMeters < $1.routeProgressMeters }

        return PreparedGPXRoute(
            formatVersion: PreparedGPXRoute.currentFormatVersion,
            name: document.name,
            sourcePointCount: sourcePointCount,
            sourceSegmentCount: document.segments.count,
            origin: origin,
            vertices: vertices,
            segments: segments,
            waypoints: waypoints,
            turnVertexIndices: turns,
            ambiguousSegmentPairs: ambiguousPairs,
            flags: RouteTopologyFlags(isLoop: isLoop, isOutAndBack: isOutAndBack,
                                      hasNearbyParallelSegments: !ambiguousPairs.isEmpty),
            totalDistanceMeters: cumulativeDistance,
            totalAscentMeters: totalAscent
        )
    }

    private struct IndexedPoint {
        var point: GPXTrackPoint
        var sourceIndex: Int
        var local: LocalPoint
    }

    private struct LocalPoint {
        var x: Double
        var y: Double
    }

    private func deduplicate(_ points: [IndexedPoint]) -> [IndexedPoint] {
        var result: [IndexedPoint] = []
        for point in points {
            guard let previous = result.last else { result.append(point); continue }
            let distance = hypot(point.local.x - previous.local.x, point.local.y - previous.local.y)
            let elevationDelta = abs((point.point.elevationMeters ?? 0) - (previous.point.elevationMeters ?? 0))
            if distance >= duplicateThresholdMeters || elevationDelta >= elevationNoiseThresholdMeters {
                result.append(point)
            }
        }
        return result
    }

    private func simplify(_ points: [IndexedPoint]) -> [IndexedPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for index in 1..<(points.count - 1) {
            let previous = result[result.count - 1]
            let current = points[index]
            let next = points[index + 1]
            let spacing = hypot(current.local.x - previous.local.x, current.local.y - previous.local.y)
            let projection = Self.project(point: current.local, ontoStart: previous.local, end: next.local)
            let lineDistance = hypot(current.local.x - projection.point.x, current.local.y - projection.point.y)
            let turn = Self.headingDifference(
                Self.bearing(from: previous.local, to: current.local),
                Self.bearing(from: current.local, to: next.local)
            )
            let elevationDeviation: Double = {
                guard let elevation = current.point.elevationMeters,
                      let start = previous.point.elevationMeters,
                      let end = next.point.elevationMeters else { return 0 }
                let expected = start + (end - start) * projection.fraction
                return abs(elevation - expected)
            }()
            if spacing >= maximumSimplifiedSpacingMeters || lineDistance >= simplificationToleranceMeters ||
                turn >= 12 || elevationDeviation >= elevationNoiseThresholdMeters {
                result.append(current)
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    private func applyRemainingMetrics(vertices: inout [PreparedRouteVertex],
                                       segments: inout [PreparedRouteSegment], totalDistance: Double) {
        for index in vertices.indices {
            vertices[index].remainingDistanceMeters = max(0, totalDistance - vertices[index].cumulativeDistanceMeters)
        }
        var remainingAscent = 0.0
        for segment in segments.reversed() {
            vertices[segment.endVertexIndex].remainingAscentMeters = max(
                vertices[segment.endVertexIndex].remainingAscentMeters, remainingAscent
            )
            remainingAscent += segment.ascentMeters
            vertices[segment.startVertexIndex].remainingAscentMeters = remainingAscent
        }
        for index in segments.indices {
            segments[index].remainingDistanceAtStartMeters = max(
                0, totalDistance - segments[index].cumulativeStartMeters
            )
            segments[index].remainingAscentAtStartMeters =
                vertices[segments[index].startVertexIndex].remainingAscentMeters
        }
    }

    private func findTurns(segments: [PreparedRouteSegment]) -> [Int] {
        guard segments.count > 1 else { return [] }
        var turns: [Int] = []
        for index in 1..<segments.count {
            let previous = segments[index - 1]
            let current = segments[index]
            guard previous.endVertexIndex == current.startVertexIndex,
                  previous.sourceSegmentIndex == current.sourceSegmentIndex else { continue }
            if Self.headingDifference(previous.bearingDegrees, current.bearingDegrees) >= turnThresholdDegrees {
                turns.append(current.startVertexIndex)
            }
        }
        return turns
    }

    private func findAmbiguousPairs(vertices: [PreparedRouteVertex],
                                    segments: [PreparedRouteSegment]) -> [RouteSegmentPair] {
        guard segments.count > 2 else { return [] }
        struct GridKey: Hashable { var x: Int; var y: Int }
        let cellSize = max(parallelCorridorMeters * 2, 50)
        var grid: [GridKey: [Int]] = [:]
        var pairs: [RouteSegmentPair] = []
        var seen = Set<RouteSegmentPair>()
        for secondIndex in segments.indices {
            let second = segments[secondIndex]
            let minimumCellX = Int(floor((second.minimumX - parallelCorridorMeters) / cellSize))
            let maximumCellX = Int(floor((second.maximumX + parallelCorridorMeters) / cellSize))
            let minimumCellY = Int(floor((second.minimumY - parallelCorridorMeters) / cellSize))
            let maximumCellY = Int(floor((second.maximumY + parallelCorridorMeters) / cellSize))
            var nearby = Set<Int>()
            for x in minimumCellX...maximumCellX {
                for y in minimumCellY...maximumCellY {
                    nearby.formUnion(grid[GridKey(x: x, y: y)] ?? [])
                }
            }

            if second.lengthMeters >= 15 {
                for firstIndex in nearby where secondIndex - firstIndex >= 2 {
                    let first = segments[firstIndex]
                    guard first.lengthMeters >= 15 else { continue }
                let headingDifference = Self.headingDifference(first.bearingDegrees, second.bearingDegrees)
                guard headingDifference <= 25 || headingDifference >= 155 else { continue }
                let firstStart = vertices[first.startVertexIndex]
                let firstEnd = vertices[first.endVertexIndex]
                let secondStart = vertices[second.startVertexIndex]
                let secondEnd = vertices[second.endVertexIndex]
                let firstMid = LocalPoint(x: (firstStart.localXMeters + firstEnd.localXMeters) / 2,
                                          y: (firstStart.localYMeters + firstEnd.localYMeters) / 2)
                let secondMid = LocalPoint(x: (secondStart.localXMeters + secondEnd.localXMeters) / 2,
                                           y: (secondStart.localYMeters + secondEnd.localYMeters) / 2)
                let firstToSecond = Self.project(point: firstMid,
                                                 ontoStart: LocalPoint(x: secondStart.localXMeters, y: secondStart.localYMeters),
                                                 end: LocalPoint(x: secondEnd.localXMeters, y: secondEnd.localYMeters))
                let secondToFirst = Self.project(point: secondMid,
                                                 ontoStart: LocalPoint(x: firstStart.localXMeters, y: firstStart.localYMeters),
                                                 end: LocalPoint(x: firstEnd.localXMeters, y: firstEnd.localYMeters))
                let distance = min(hypot(firstMid.x - firstToSecond.point.x, firstMid.y - firstToSecond.point.y),
                                   hypot(secondMid.x - secondToFirst.point.x, secondMid.y - secondToFirst.point.y))
                guard distance <= parallelCorridorMeters else { continue }
                    let pair = RouteSegmentPair(firstSegmentIndex: firstIndex, secondSegmentIndex: secondIndex)
                    if seen.insert(pair).inserted { pairs.append(pair) }
                }
            }

            let insertMinimumX = Int(floor(second.minimumX / cellSize))
            let insertMaximumX = Int(floor(second.maximumX / cellSize))
            let insertMinimumY = Int(floor(second.minimumY / cellSize))
            let insertMaximumY = Int(floor(second.maximumY / cellSize))
            for x in insertMinimumX...insertMaximumX {
                for y in insertMinimumY...insertMaximumY {
                    grid[GridKey(x: x, y: y), default: []].append(secondIndex)
                }
            }
        }
        return pairs.sorted {
            ($0.firstSegmentIndex, $0.secondSegmentIndex) < ($1.firstSegmentIndex, $1.secondSegmentIndex)
        }
    }

    private func projectWaypoint(_ waypoint: GPXWaypoint, origin: RouteCoordinate,
                                 vertices: [PreparedRouteVertex], segments: [PreparedRouteSegment]) -> PreparedRouteWaypoint? {
        let point = Self.localPoint(latitude: waypoint.latitude, longitude: waypoint.longitude, origin: origin)
        var best: (segment: PreparedRouteSegment, fraction: Double, distance: Double)?
        for segment in segments {
            let start = vertices[segment.startVertexIndex]
            let end = vertices[segment.endVertexIndex]
            let projection = Self.project(point: point,
                                          ontoStart: LocalPoint(x: start.localXMeters, y: start.localYMeters),
                                          end: LocalPoint(x: end.localXMeters, y: end.localYMeters))
            let distance = hypot(point.x - projection.point.x, point.y - projection.point.y)
            if best == nil || distance < best!.distance { best = (segment, projection.fraction, distance) }
        }
        guard let best else { return nil }
        return PreparedRouteWaypoint(
            name: waypoint.name,
            coordinate: RouteCoordinate(latitude: waypoint.latitude, longitude: waypoint.longitude),
            elevationMeters: waypoint.elevationMeters,
            routeProgressMeters: best.segment.cumulativeStartMeters + best.fraction * best.segment.lengthMeters,
            distanceFromRouteMeters: best.distance
        )
    }

    private func elevationDifference(from start: Double?, to end: Double?) -> Double {
        guard let start, let end, start.isFinite, end.isFinite else { return .nan }
        return end - start
    }

    private static func localPoint(for point: GPXTrackPoint, origin: RouteCoordinate) -> LocalPoint {
        localPoint(latitude: point.latitude, longitude: point.longitude, origin: origin)
    }

    private static func localPoint(latitude: Double, longitude: Double, origin: RouteCoordinate) -> LocalPoint {
        let radians = Double.pi / 180
        let x = (longitude - origin.longitude) * radians * 6_371_000 * cos(origin.latitude * radians)
        let y = (latitude - origin.latitude) * radians * 6_371_000
        return LocalPoint(x: x, y: y)
    }

    private static func project(point: LocalPoint, ontoStart start: LocalPoint,
                                end: LocalPoint) -> (point: LocalPoint, fraction: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (start, 0) }
        let fraction = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        return (LocalPoint(x: start.x + fraction * dx, y: start.y + fraction * dy), fraction)
    }

    private static func bearing(from start: LocalPoint, to end: LocalPoint) -> Double {
        normalizedDegrees(atan2(end.x - start.x, end.y - start.y) * 180 / .pi)
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
