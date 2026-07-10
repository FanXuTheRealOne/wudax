import Foundation
import Combine

@MainActor
final class OfflineResourceManager: ObservableObject {
    @Published private(set) var status = OfflineResourceStatus(mode: .unavailable, progress: 0,
                                                                 estimatedSizeMB: 0, updatedAt: nil,
                                                                 integrityMessage: "尚未准备路线资源", isReady: false)
    @Published private(set) var routeFileURL: URL?

    private let fileManager = FileManager.default

    func prepare(analyzedGPX: AnalyzedGPX, originalGPXData: Data? = nil) {
        do {
            let directory = try applicationSupportDirectory().appendingPathComponent("Routes", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let resourceID = UUID().uuidString
            let fileURL = directory.appendingPathComponent("\(resourceID).gpx.json")
            let data = try JSONEncoder().encode(analyzedGPX.document.copyForPlanning())
            try data.write(to: fileURL, options: .atomic)
            if let originalGPXData {
                try originalGPXData.write(to: directory.appendingPathComponent("\(resourceID).gpx"), options: .atomic)
            }
            routeFileURL = fileURL
            status = OfflineResourceStatus(mode: .routeOnly, progress: 1, estimatedSizeMB: Double(data.count) / 1_000_000,
                                           updatedAt: Date(), integrityMessage: "原始 GPX、海拔和路线进度已本地保存；当前没有配置地图瓦片源，使用仅路线离线模式。", isReady: true)
        } catch {
            status = OfflineResourceStatus(mode: .unavailable, progress: 0, estimatedSizeMB: 0,
                                           updatedAt: nil, integrityMessage: "路线资源保存失败：\(error.localizedDescription)", isReady: false)
        }
    }

    func clear() {
        if let routeFileURL { try? fileManager.removeItem(at: routeFileURL) }
        routeFileURL = nil
        status = .init(mode: .unavailable, progress: 0, estimatedSizeMB: 0, updatedAt: nil,
                       integrityMessage: "尚未准备路线资源", isReady: false)
    }

    private func applicationSupportDirectory() throws -> URL {
        try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
}
