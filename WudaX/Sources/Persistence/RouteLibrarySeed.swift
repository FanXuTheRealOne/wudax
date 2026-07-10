import Foundation

// MARK: - 路线库首次启动的示例数据
// 这些记录会被真正写入本地库(可增删改查),不是写死在 UI 里。
// 几何折线用于缩略图与"打开路线";距离/爬升/用时按展示值精确设置。

enum RouteLibrarySeed {
    static var records: [RouteRecord] {
        [
            make(name: "武功山 · 龙山村—发云界", author: "Leven Mao",
                 daysAgo: 3, distanceKm: 24.6, ascentM: 1780, hours: 9.5,
                 baseLat: 27.46, baseLon: 114.18, seed: 1),
            make(name: "Yulong Snow Mountain", author: "山野_Kepler",
                 daysAgo: 20, distanceKm: 18.3, ascentM: 1260, hours: 6.75,
                 baseLat: 27.10, baseLon: 100.17, seed: 2),
            make(name: "Dagu Glacier", author: "川西老王",
                 daysAgo: 42, distanceKm: 11.2, ascentM: 680, hours: 4.333,
                 baseLat: 32.25, baseLon: 102.75, seed: 3),
            make(name: "Siguniang Mountain", author: "Alpine_Rui",
                 daysAgo: 60, distanceKm: 16.8, ascentM: 1250, hours: 7.25,
                 baseLat: 31.10, baseLon: 102.90, seed: 4)
        ]
    }

    private static func make(name: String, author: String, daysAgo: Int,
                             distanceKm: Double, ascentM: Double, hours: Double,
                             baseLat: Double, baseLon: Double, seed: Int) -> RouteRecord {
        let recordedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let points = meander(baseLat: baseLat, baseLon: baseLon, count: 64,
                             ascentM: ascentM, start: recordedAt, hours: hours, seed: seed)
        let document = GPXDocument(
            name: name,
            creator: "WUDAX Sample",
            author: author,
            recordedStartAt: recordedAt,
            segments: [GPXTrackSegment(points: points)],
            waypoints: [],
            purpose: .recordedActivity
        )
        let provenance = RouteProvenance(
            authorName: author,
            creatorSoftware: "两步路",
            recordedAt: recordedAt,
            recordedDurationSeconds: hours * 3600,
            distanceMeters: distanceKm * 1000,
            ascentMeters: ascentM,
            maxElevationMeters: points.compactMap(\.elevationMeters).max(),
            isRecordedActivity: true
        )
        return RouteRecord(
            name: name,
            createdAt: recordedAt,
            provenance: provenance,
            distanceKm: distanceKm,
            ascentMeters: ascentM,
            estimatedHours: hours,
            riskLevel: .coarse(distanceKm: distanceKm, ascentM: ascentM, quality: 90),
            qualityScore: 90,
            document: document
        )
    }

    /// 生成一条确定性的蜿蜒折线 + 爬升-下降海拔剖面(仅用于缩略图/打开)。
    private static func meander(baseLat: Double, baseLon: Double, count: Int,
                                ascentM: Double, start: Date, hours: Double, seed: Int) -> [GPXTrackPoint] {
        (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let phase = Double(seed) * 1.3
            // 主行进方向 + 侧向蜿蜒
            let lat = baseLat + t * 0.075 + sin(t * .pi * 3 + phase) * 0.012
            let lon = baseLon + t * 0.055 + cos(t * .pi * 2.2 + phase) * 0.014
            // 爬升到中段再下降
            let ele = 1000 + sin(t * .pi) * ascentM
            let time = start.addingTimeInterval(t * hours * 3600)
            return GPXTrackPoint(latitude: lat, longitude: lon, elevationMeters: ele,
                                 time: time, speedMetersPerSecond: nil,
                                 heartRateBPM: nil, cadenceRPM: nil)
        }
    }
}
