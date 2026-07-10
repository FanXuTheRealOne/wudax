import Foundation
import Combine

@MainActor
final class OfflineResourceManager: ObservableObject {
    @Published private(set) var status = OfflineResourceStatus(mode: .unavailable, progress: 0,
                                                                 estimatedSizeMB: 0, updatedAt: nil,
                                                                 integrityMessage: "尚未准备路线资源", isReady: false)
    @Published private(set) var routeFileURL: URL?
    @Published private(set) var preparedRouteFileURL: URL?
    @Published private(set) var originalGPXFileURL: URL?

    private let fileManager = FileManager.default
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    func prepare(analyzedGPX: AnalyzedGPX,
                 preparedRoute: PreparedGPXRoute? = nil,
                 originalGPXData: Data? = nil) {
        do {
            let directory = try applicationSupportDirectory().appendingPathComponent("Routes", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let resourceID = UUID().uuidString
            let fileURL = directory.appendingPathComponent("\(resourceID).gpx.json")
            let data = try JSONEncoder().encode(analyzedGPX.document.copyForPlanning())
            try data.write(to: fileURL, options: .atomic)
            var totalBytes = data.count
            if let preparedRoute {
                let preparedURL = directory.appendingPathComponent("\(resourceID).route.json")
                let preparedData = try JSONEncoder().encode(preparedRoute)
                try preparedData.write(to: preparedURL, options: .atomic)
                preparedRouteFileURL = preparedURL
                totalBytes += preparedData.count
            } else {
                preparedRouteFileURL = nil
            }
            if let originalGPXData {
                let originalURL = directory.appendingPathComponent("\(resourceID).gpx")
                try originalGPXData.write(to: originalURL, options: .atomic)
                originalGPXFileURL = originalURL
                totalBytes += originalGPXData.count
            } else {
                originalGPXFileURL = nil
            }
            routeFileURL = fileURL
            status = OfflineResourceStatus(mode: .routeOnly, progress: 1,
                                           estimatedSizeMB: Double(totalBytes) / 1_000_000,
                                           updatedAt: Date(),
                                           integrityMessage: "原始 GPX、预处理路线、海拔与匹配索引已本地保存；未配置地图瓦片时仍可离线路线匹配。",
                                           isReady: true)
        } catch {
            status = OfflineResourceStatus(mode: .unavailable, progress: 0, estimatedSizeMB: 0,
                                           updatedAt: nil, integrityMessage: "路线资源保存失败：\(error.localizedDescription)", isReady: false)
        }
    }

    func clear() {
        if let routeFileURL { try? fileManager.removeItem(at: routeFileURL) }
        if let preparedRouteFileURL { try? fileManager.removeItem(at: preparedRouteFileURL) }
        if let originalGPXFileURL { try? fileManager.removeItem(at: originalGPXFileURL) }
        routeFileURL = nil
        preparedRouteFileURL = nil
        originalGPXFileURL = nil
        status = .init(mode: .unavailable, progress: 0, estimatedSizeMB: 0, updatedAt: nil,
                       integrityMessage: "尚未准备路线资源", isReady: false)
    }

    private func applicationSupportDirectory() throws -> URL {
        if let baseDirectory {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            return baseDirectory
        }
        return try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
    }
}
