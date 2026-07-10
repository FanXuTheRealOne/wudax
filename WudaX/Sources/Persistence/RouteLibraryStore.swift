import Foundation
import Combine

// MARK: - 持久化的历史 GPX 路线记录

/// 一条保存在本地路线库中的 GPX 记录(首页「历史 GPX 记录」列表的数据源)。
/// 保留完整 `GPXDocument` 以便重新打开、规划、画缩略图。
struct RouteRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var provenance: RouteProvenance
    var distanceKm: Double
    var ascentMeters: Double
    var estimatedHours: Double
    var riskLevel: RiskLevel
    var qualityScore: Int
    var document: GPXDocument

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date,
         provenance: RouteProvenance,
         distanceKm: Double,
         ascentMeters: Double,
         estimatedHours: Double,
         riskLevel: RiskLevel,
         qualityScore: Int,
         document: GPXDocument) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.provenance = provenance
        self.distanceKm = distanceKm
        self.ascentMeters = ascentMeters
        self.estimatedHours = estimatedHours
        self.riskLevel = riskLevel
        self.qualityScore = qualityScore
        self.document = document
    }

    /// 重新分析文档,得到规划所需的 AnalyzedGPX。
    func analyzed() -> AnalyzedGPX { GPXAnalyzer().analyze(document) }

    /// 经纬度折线(用于缩略图)。
    var coordinates: [(lat: Double, lon: Double)] {
        document.points.map { ($0.latitude, $0.longitude) }
    }

    var estimatedHoursText: String {
        let h = Int(estimatedHours)
        let m = Int((estimatedHours - Double(h)) * 60)
        return "\(h)h\(String(format: "%02d", m))m"
    }
}

extension RiskLevel {
    /// 由距离/爬升/质量粗估风险等级(入库时用,无需完整规划)。
    static func coarse(distanceKm: Double, ascentM: Double, quality: Int) -> RiskLevel {
        var score = 0
        if distanceKm > 30 || ascentM > 2200 { score += 3 }
        else if distanceKm > 22 || ascentM > 1600 { score += 2 }
        else if distanceKm > 12 || ascentM > 800 { score += 1 }
        if quality < 60 { score += 1 }
        switch score {
        case 0: return .low
        case 1: return .medium
        case 2: return .mediumHigh
        default: return .high
        }
    }
}

extension RouteRecord {
    /// 从导入分析结果构造记录。
    init(analyzedGPX: AnalyzedGPX, createdAt: Date) {
        let route = Route(analyzedGPX: analyzedGPX)
        self.init(
            name: route.name,
            createdAt: createdAt,
            provenance: route.provenance ?? RouteProvenance(analyzedGPX: analyzedGPX),
            distanceKm: route.distanceKm,
            ascentMeters: route.ascentM,
            estimatedHours: route.estimatedHours,
            riskLevel: .coarse(distanceKm: route.distanceKm, ascentM: route.ascentM, quality: route.qualityScore),
            qualityScore: route.qualityScore,
            document: analyzedGPX.document
        )
    }
}

// MARK: - 本地路线库(可增删改查,JSON 永久化)

@MainActor
final class RouteLibraryStore: ObservableObject {
    @Published private(set) var records: [RouteRecord] = []
    private let directory: URL
    private let fileURL: URL

    init(directory: URL? = nil, seedIfEmpty: Bool = true) {
        let base = directory
            ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.directory = base
        self.fileURL = base.appendingPathComponent("wudax-routes.json")
        load()
        if records.isEmpty && seedIfEmpty {
            records = RouteLibrarySeed.records
            persist()
        }
    }

    // MARK: CRUD

    /// 新增或更新(按 id 去重),置顶。
    func upsert(_ record: RouteRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        persist()
    }

    func delete(_ record: RouteRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        persist()
    }

    func rename(_ record: RouteRecord, to newName: String) {
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[idx].name = newName
        persist()
    }

    func record(id: UUID) -> RouteRecord? { records.first { $0.id == id } }

    // MARK: 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RouteRecord].self, from: data) else { return }
        records = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 保存失败不阻断浏览;下次启动仍读旧数据。
        }
    }
}
