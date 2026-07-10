import Foundation

/// 轨迹原作者档案 —— 这条 GPX 是谁走的、用了多久。
/// 与本 App 用户的 `FatigueProfile` 严格区分:大多数人是下载别人的 GPX 来走,
/// 作者不是使用者。作者信息缺失时保持为空,绝不冒认当前用户。
struct RouteProvenance: Codable, Equatable, Sendable {
    var authorName: String?
    var creatorSoftware: String?
    var recordedAt: Date?
    var recordedDurationSeconds: TimeInterval?
    var distanceMeters: Double
    var ascentMeters: Double
    var maxElevationMeters: Double?
    var isRecordedActivity: Bool

    var hasAuthor: Bool { (authorName?.isEmpty == false) }
    var displayAuthor: String { hasAuthor ? authorName! : "未署名轨迹" }

    /// 原作者平均配速(秒/公里)
    var paceSecondsPerKm: Double? {
        guard let recordedDurationSeconds, distanceMeters > 100 else { return nil }
        return recordedDurationSeconds / (distanceMeters / 1000)
    }

    /// 原作者平均速度(公里/小时)
    var averageSpeedKmh: Double? {
        guard let recordedDurationSeconds, recordedDurationSeconds > 0 else { return nil }
        return (distanceMeters / 1000) / (recordedDurationSeconds / 3600)
    }

    var recordedDurationText: String? {
        guard let s = recordedDurationSeconds, s > 0 else { return nil }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))m" : "\(m)m"
    }

    var paceText: String? {
        guard let pace = paceSecondsPerKm else { return nil }
        let m = Int(pace) / 60
        let s = Int(pace) % 60
        return "\(m)'\(String(format: "%02d", s))\"/km"
    }
}

extension RouteProvenance {
    init(analyzedGPX: AnalyzedGPX) {
        let doc = analyzedGPX.document
        let stats = analyzedGPX.statistics
        self.init(
            authorName: doc.author,
            creatorSoftware: doc.creator,
            recordedAt: doc.recordedStartAt,
            recordedDurationSeconds: stats.recordedDuration,
            distanceMeters: stats.distanceMeters,
            ascentMeters: stats.ascentMeters,
            maxElevationMeters: stats.maximumElevationMeters,
            isRecordedActivity: doc.purpose == .recordedActivity
        )
    }
}
