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
