import Foundation

// MARK: - 路线三维海拔剖面分析器
// GPX 的第三维(海拔)带有强 GPS 噪声:实测城市平路轨迹相邻点海拔平均抖动
// 1.1 m、最大近 10 m,逐点累计会把平路算出上百米"假爬升"。
// 本工具先做距离窗口平滑,再基于平滑剖面回答:
//   当前海拔/脚下坡度是多少?前方一段是上坡还是下坡?坡型如何、最陡多少?
// 这是行中 Agent 回答「等会是下坡吗」的事实来源。

struct RouteElevationProfiler {

    struct Sample {
        var distance: Double     // 沿路线累计距离(米)
        var elevation: Double    // 平滑后海拔(米)
    }

    /// 一段路的坡度趋势(基于平滑剖面)。
    struct Trend: Equatable {
        enum Pattern: String {
            case flat = "基本平缓"
            case climb = "持续上坡"
            case descent = "持续下坡"
            case rolling = "起伏路段"
            case climbThenDescent = "先升后降"
            case descentThenClimb = "先降后升"
        }

        var spanMeters: Double
        var netMeters: Double
        var ascentMeters: Double
        var descentMeters: Double
        var averageGradePercent: Double
        /// 100 m 微段中绝对值最大的坡度(带符号)。
        var steepestGradePercent: Double
        var pattern: Pattern

        /// 给 LLM/UI 的中文一句话。
        var summary: String {
            switch pattern {
            case .flat:
                return "基本平缓"
            case .climb:
                var text = String(format: "持续上坡,累计升约 %.0f m(平均坡度 +%.0f%%)", ascentMeters, abs(averageGradePercent))
                if steepestGradePercent >= 15 { text += String(format: ",最陡约 %.0f%%", steepestGradePercent) }
                return text
            case .descent:
                var text = String(format: "持续下坡,累计降约 %.0f m(平均坡度 -%.0f%%)", descentMeters, abs(averageGradePercent))
                if steepestGradePercent <= -15 { text += String(format: ",最陡约 %.0f%%,注意膝盖", abs(steepestGradePercent)) }
                return text
            case .rolling:
                return String(format: "起伏路段,累计升 %.0f m/降 %.0f m", ascentMeters, descentMeters)
            case .climbThenDescent:
                return String(format: "先升约 %.0f m,后降约 %.0f m", ascentMeters, descentMeters)
            case .descentThenClimb:
                return String(format: "先降约 %.0f m,后升约 %.0f m", descentMeters, ascentMeters)
            }
        }
    }

    let samples: [Sample]
    let totalDistanceMeters: Double

    /// 从预处理路线构建:抽取带海拔的顶点并按 ±window 距离窗口滑动平均平滑。
    init?(route: PreparedGPXRoute, smoothingWindowMeters: Double = 60) {
        let raw: [(Double, Double)] = route.vertices.compactMap { vertex in
            vertex.elevationMeters.map { (vertex.cumulativeDistanceMeters, $0) }
        }
        guard raw.count >= 2 else { return nil }

        // 双指针滑动窗口均值:O(n)。
        var smoothed: [Sample] = []
        smoothed.reserveCapacity(raw.count)
        var lo = 0, hi = 0
        var windowSum = 0.0
        for (distance, _) in raw {
            while hi < raw.count, raw[hi].0 <= distance + smoothingWindowMeters {
                windowSum += raw[hi].1
                hi += 1
            }
            while lo < hi, raw[lo].0 < distance - smoothingWindowMeters {
                windowSum -= raw[lo].1
                lo += 1
            }
            smoothed.append(Sample(distance: distance, elevation: windowSum / Double(hi - lo)))
        }
        self.samples = smoothed
        self.totalDistanceMeters = route.totalDistanceMeters
    }

    /// 任意进度处的平滑海拔(线性插值)。
    func elevation(atProgress progress: Double) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if progress <= first.distance { return first.elevation }
        if progress >= last.distance { return last.elevation }
        // 二分找区间
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].distance <= progress { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let t = (progress - a.distance) / max(b.distance - a.distance, 0.01)
        return a.elevation + (b.elevation - a.elevation) * t
    }

    /// 某进度处"脚下"的坡度(前后 window/2 的平均,%)。
    func gradePercent(atProgress progress: Double, windowMeters: Double = 100) -> Double? {
        let half = windowMeters / 2
        guard let ahead = elevation(atProgress: progress + half),
              let behind = elevation(atProgress: progress - half) else { return nil }
        let span = min(progress + half, totalDistanceMeters) - max(progress - half, 0)
        guard span > 10 else { return nil }
        return (ahead - behind) / span * 100
    }

    /// [from, from+span] 区间的趋势;区间落在路线外或过短时为 nil。
    func trend(fromProgress from: Double, spanMeters span: Double) -> Trend? {
        let start = max(from, 0)
        let end = min(from + span, totalDistanceMeters)
        guard end - start >= 50 else { return nil }

        // 平滑样本裁剪到区间,并用插值补齐端点。
        var section: [Sample] = []
        if let e = elevation(atProgress: start) { section.append(Sample(distance: start, elevation: e)) }
        section.append(contentsOf: samples.filter { $0.distance > start && $0.distance < end })
        if let e = elevation(atProgress: end) { section.append(Sample(distance: end, elevation: e)) }
        guard section.count >= 2 else { return nil }

        let net = section[section.count - 1].elevation - section[0].elevation
        var ascent = 0.0, descent = 0.0
        for i in 1..<section.count {
            let delta = section[i].elevation - section[i - 1].elevation
            if delta > 0 { ascent += delta } else { descent -= delta }
        }
        let length = end - start
        let averageGrade = net / length * 100

        // 100 m 微段最陡坡度(带符号,取绝对值最大者)。
        var steepest = 0.0
        var cursor = start
        while cursor + 100 <= end {
            if let a = elevation(atProgress: cursor), let b = elevation(atProgress: cursor + 100) {
                let grade = (b - a)
                if abs(grade) > abs(steepest) { steepest = grade }
            }
            cursor += 50
        }
        if steepest == 0 { steepest = averageGrade }

        let midpoint = start + length / 2
        let firstHalfNet = (elevation(atProgress: midpoint) ?? 0) - section[0].elevation
        let secondHalfNet = section[section.count - 1].elevation - (elevation(atProgress: midpoint) ?? 0)

        let significant = max(6.0, length * 0.015)
        let pattern: Trend.Pattern
        if net >= significant, descent <= max(ascent * 0.35, 5) {
            pattern = .climb
        } else if net <= -significant, ascent <= max(descent * 0.35, 5) {
            pattern = .descent
        } else if firstHalfNet >= significant, secondHalfNet <= -significant {
            pattern = .climbThenDescent
        } else if firstHalfNet <= -significant, secondHalfNet >= significant {
            pattern = .descentThenClimb
        } else if ascent + descent >= max(length * 0.04, 20) {
            pattern = .rolling
        } else {
            pattern = .flat
        }

        return Trend(spanMeters: length,
                     netMeters: net,
                     ascentMeters: ascent,
                     descentMeters: descent,
                     averageGradePercent: averageGrade,
                     steepestGradePercent: steepest,
                     pattern: pattern)
    }
}
