import Foundation

struct GPXAnalyzer {
    var longGapThreshold: TimeInterval = 30 * 60
    var repeatedCoordinateThresholdMeters = 0.75
    /// GPS altitude commonly jitters by a few metres while a hiker is still.
    /// Changes below this deadband are not counted as climb/descent.
    var elevationNoiseThresholdMeters = 2.0
    /// Deliberately generous for a hiking file; this catches teleporting GPS
    /// points without rejecting a bike/car recording that a user may import.
    var maximumReasonableSpeedMetersPerSecond = 30.0

    func analyze(_ document: GPXDocument) -> AnalyzedGPX {
        var distance = 0.0
        var ascent = 0.0
        var descent = 0.0
        var elevations: [Double] = []
        var times: [Date] = []
        var maximumGap = 0.0
        var regressions = 0
        var longGaps = 0
        var repeats = 0
        var unreasonableSpeeds = 0

        for segment in document.segments {
            var previousPoint: GPXTrackPoint?
            var elevationBaseline: Double?

            for point in segment.points {
                if let elevation = point.elevationMeters, elevation.isFinite {
                    elevations.append(elevation)
                    if elevationBaseline == nil { elevationBaseline = elevation }
                }
                if let time = point.time { times.append(time) }

                if let previousPoint {
                    let meters = Self.distance(from: previousPoint, to: point)
                    distance += meters
                    if meters <= repeatedCoordinateThresholdMeters { repeats += 1 }

                    if let previousElevation = previousPoint.elevationMeters,
                       let currentElevation = point.elevationMeters,
                       previousElevation.isFinite, currentElevation.isFinite {
                        if elevationBaseline == nil { elevationBaseline = previousElevation }
                        if let baseline = elevationBaseline {
                            let delta = currentElevation - baseline
                            if delta >= elevationNoiseThresholdMeters {
                                ascent += delta
                                elevationBaseline = currentElevation
                            } else if delta <= -elevationNoiseThresholdMeters {
                                descent += -delta
                                elevationBaseline = currentElevation
                            }
                        }
                    }

                    if let previousTime = previousPoint.time, let currentTime = point.time {
                        let gap = currentTime.timeIntervalSince(previousTime)
                        if gap < 0 {
                            regressions += 1
                        } else {
                            maximumGap = max(maximumGap, gap)
                            if gap > longGapThreshold { longGaps += 1 }
                            if gap > 0,
                               meters / gap > maximumReasonableSpeedMetersPerSecond {
                                unreasonableSpeeds += 1
                            }
                        }
                    }
                }
                previousPoint = point
            }
        }

        let allPoints = document.points
        let loopDistance: Double = {
            guard let first = allPoints.first, let last = allPoints.last else { return .infinity }
            return Self.distance(from: first, to: last)
        }()
        let duration: TimeInterval? = {
            guard let first = times.min(), let last = times.max() else { return nil }
            return max(0, last.timeIntervalSince(first))
        }()

        var issues: [DataQualityIssue] = []
        if allPoints.count < 2 {
            issues.append(.init(kind: .tooFewPoints, count: allPoints.count, message: "有效轨迹点不足"))
        }
        if document.ignoredPointCount > 0 {
            issues.append(.init(kind: .invalidCoordinate,
                                count: document.ignoredPointCount,
                                message: String(format: "忽略了 %d 个坐标无效的轨迹点", document.ignoredPointCount)))
        }
        let missingElevation = allPoints.filter { $0.elevationMeters == nil }.count
        if missingElevation > 0 {
            issues.append(.init(kind: .missingElevation,
                                count: missingElevation,
                                message: String(format: "%d 个轨迹点缺少海拔", missingElevation)))
        }
        let missingTime = allPoints.filter { $0.time == nil }.count
        if missingTime > 0 {
            issues.append(.init(kind: .missingTime,
                                count: missingTime,
                                message: String(format: "%d 个轨迹点缺少时间", missingTime)))
        }
        if regressions > 0 {
            issues.append(.init(kind: .timeRegression,
                                count: regressions,
                                message: String(format: "检测到 %d 处时间倒退", regressions)))
        }
        if longGaps > 0 {
            issues.append(.init(kind: .longTimeGap,
                                count: longGaps,
                                message: String(format: "检测到 %d 处超过 30 分钟的记录中断", longGaps)))
        }
        if repeats > 0 {
            issues.append(.init(kind: .repeatedCoordinate,
                                count: repeats,
                                message: String(format: "检测到 %d 处重复坐标或停留", repeats)))
        }
        if unreasonableSpeeds > 0 {
            issues.append(.init(kind: .unreasonableSpeed,
                                count: unreasonableSpeeds,
                                message: String(format: "检测到 %d 处不合理的瞬时速度，相关点位可信度降低", unreasonableSpeeds)))
        }

        return AnalyzedGPX(
            document: document,
            statistics: TrackStatistics(
                distanceMeters: distance,
                ascentMeters: ascent,
                descentMeters: descent,
                minimumElevationMeters: elevations.min(),
                maximumElevationMeters: elevations.max(),
                recordedDuration: duration,
                maximumTimeGap: maximumGap,
                isLoop: loopDistance <= max(100, distance * 0.02)
            ),
            qualityIssues: issues
        )
    }

    private static func distance(from a: GPXTrackPoint, to b: GPXTrackPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLatitude = (b.latitude - a.latitude) * .pi / 180
        let deltaLongitude = (b.longitude - a.longitude) * .pi / 180
        let haversine = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return earthRadius * 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
    }
}
