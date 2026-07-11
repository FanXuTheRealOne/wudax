import Foundation
import Combine

struct StoredTrip: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var completedAt: Date
    var route: GPXDocument?
    var summary: TripSummary
    var events: [TripEvent]
    var reviewAnswers: [String: String]
    var trainingAdvice: TrainingAdvice
    var recordedTrack: [RecordedTrackPoint] = []
    /// 本次行程走的是路线库里哪条记录(路线详情页按此聚合行走 log);旧数据为 nil。
    var routeRecordID: UUID?
    var startedAt: Date?
    var endedByRetreat: Bool?
}

@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var trips: [StoredTrip] = []
    private let directory: URL
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        self.directory = base
        self.fileURL = base.appendingPathComponent("wudax-trips.json")
        load()
    }

    func save(_ trip: StoredTrip) {
        trips.removeAll { $0.id == trip.id }
        trips.insert(trip, at: 0)
        persist()
    }

    func delete(_ trip: StoredTrip) {
        trips.removeAll { $0.id == trip.id }
        persist()
    }

    /// 某条库内路线的全部行走记录,最近一次在前。
    func trips(forRoute id: UUID) -> [StoredTrip] {
        trips.filter { $0.routeRecordID == id }
            .sorted { $0.completedAt > $1.completedAt }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StoredTrip].self, from: data) else { return }
        trips = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(trips)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 保存失败不会影响行后报告继续展示。
        }
    }
}
