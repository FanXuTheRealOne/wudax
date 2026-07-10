import Foundation

struct GPXAnalyzer {
    var longGapThreshold: TimeInterval = 30 * 60
    var repeatedCoordinateThresholdMeters = 0.75

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

        for segment in document.segments {
            for point in segment.points {
                if let elevation = point.elevationMeters { elevations.append(elevation) }
                if let time = point.time { times.append(time) }
            }
            for pair in zip(segment.points, segment.points.dropFirst()) {
                let meters = Self.distance(from: pair.0, to: pair.1)
                distance += meters
                if meters <= repeatedCoordinateThresholdMeters { repeats += 1 }

                if let previousElevation = pair.0.elevationMeters,
                   let currentElevation = pair.1.elevationMeters {
                    let delta = currentElevation - previousElevation
                    if delta > 0 { ascent += delta }
                    if delta < 0 { descent += -delta }
                }

                if let previousTime = pair.0.time, let currentTime = pair.1.time {
                    let gap = currentTime.timeIntervalSince(previousTime)
                    if gap < 0 { regressions += 1 }
                    if gap > longGapThreshold { longGaps += 1 }
                    maximumGap = max(maximumGap, gap)
                }
            }
        }

        let allPoints = document.points
        let loopDistance: Double = {
            guard let first = allPoints.first, let last = allPoints.last else { return .infinity }
            return Self.distance(from: first, to: last)
        }()
        let duration: TimeInterval? = {
            guard let first = times.min(), let last = times.max() else { return nil }
            return last.timeIntervalSince(first)
        }()

        var issues: [DataQualityIssue] = []
        if allPoints.count < 2 {
            issues.append(.init(kind: .tooFewPoints, count: allPoints.count, message: "有效轨迹点不足"))
        }
        let missingElevation = allPoints.filter { $0.elevationMeters == nil }.count
        if missingElevation > 0 {
            issues.append(.init(kind: .missingElevation, count: missingElevation, message: "\(missingElevation) 个轨迹点缺少海拔"))
        }
        let missingTime = allPoints.filter { $0.time == nil }.count
        if missingTime > 0 {
            issues.append(.init(kind: .missingTime, count: missingTime, message: "\(missingTime) 个轨迹点缺少时间"))
        }
        if regressions > 0 {
            issues.append(.init(kind: .timeRegression, count: regressions, message: "检测到 \(regressions) 处时间倒退"))
        }
        if longGaps > 0 {
            issues.append(.init(kind: .longTimeGap, count: longGaps, message: "检测到 \(longGaps) 处超过 30 分钟的记录中断"))
        }
        if repeats > 0 {
            issues.append(.init(kind: .repeatedCoordinate, count: repeats, message: "检测到 \(repeats) 处重复坐标或停留"))
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
        return earthRadius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}

