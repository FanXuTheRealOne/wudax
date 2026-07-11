import Foundation
import Combine

@MainActor
final class PlanningCoordinator: ObservableObject {
    enum Stage: Equatable {
        case idle, collecting, routeImported, ready
    }

    enum GPXImportPhase: Equatable {
        case idle
        case importing
        case imported
        case failed
    }

    struct ChatItem: Identifiable, Equatable {
        let id = UUID()
        var role: Role
        var text: String
        var card: Card?

        enum Role: Equatable { case assistant, user, status }
        enum Card: Equatable {
            case experience
            case route
            case report
        }
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var analyzedGPX: AnalyzedGPX?
    @Published private(set) var importedGPXData: Data?
    @Published private(set) var chat: [ChatItem] = []
    @Published private(set) var importPhase: GPXImportPhase = .idle
    @Published var importError: String?
    @Published var experience = HikerExperience.load()

    /// 行中实时读取的健康数据(行前不再请求授权)。
    @Published private(set) var healthSnapshot: HealthSnapshot?
    let healthKit = HealthKitService()

    private let parser = GPXParser()
    private let analyzer = GPXAnalyzer()
    private var healthKitCancellable: AnyCancellable?
    private let minimumVisibleImportDurationNanoseconds: UInt64 = 350_000_000

    init() {
        healthKitCancellable = healthKit.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var canImportGPX: Bool { stage != .idle }
    var experienceComplete: Bool { experience.isComplete }

    func reset() {
        stage = .idle
        analyzedGPX = nil
        importedGPXData = nil
        chat = []
        importPhase = .idle
        importError = nil
        experience = HikerExperience.load()
    }

    func begin() async {
        guard stage == .idle else { return }
        stage = .collecting
        addAssistant("行前只需要两件事:你走过最难的一次,和这次的 GPX 轨迹。健康与手表数据会在行程中实时读取。")
        if !experience.isComplete {
            addAssistant("先了解你的经验上限,用来判断这条路线对你的真实难度。", card: .experience)
        } else {
            addAssistant("已记住你的经验(最难 \(fmt(experience.hardestDistanceKm)) km / 拔高 \(Int(experience.hardestAscentM)) m / 最高 \(Int(experience.highestAltitudeM)) m / \(fmt(experience.longestDurationH)) h)。现在导入本次 GPX。", card: .route)
        }
    }

    // MARK: 过往经历作答

    func answerHardestDistance(_ km: Double) {
        experience.hardestDistanceKm = km; experience.save()
        addUser("走过最难一次距离:\(fmt(km)) km")
        promptNextExperienceOrRoute()
    }
    func answerHardestAscent(_ m: Double) {
        experience.hardestAscentM = m; experience.save()
        addUser("那次累计拔高:\(Int(m)) m")
        promptNextExperienceOrRoute()
    }
    func answerHighestAltitude(_ m: Double) {
        experience.highestAltitudeM = m; experience.save()
        addUser("走过的最高海拔:\(Int(m)) m")
        promptNextExperienceOrRoute()
    }
    func answerLongestDuration(_ h: Double) {
        experience.longestDurationH = h; experience.save()
        addUser("那次总耗时:\(fmt(h)) 小时")
        promptNextExperienceOrRoute()
    }

    private func promptNextExperienceOrRoute() {
        if experience.isComplete, analyzedGPX == nil,
           !chat.contains(where: { $0.card == .route }) {
            addAssistant("经验已记录。现在导入本次路线 GPX,我会和你的经验上限做交叉比对。", card: .route)
        }
    }

    func importGPXWithProgress(from url: URL) async {
        importPhase = .importing
        importError = nil
        await Task.yield()
        try? await Task.sleep(nanoseconds: minimumVisibleImportDurationNanoseconds)
        importGPX(from: url)
    }

    func importGPX(from url: URL) {
        if importPhase != .importing {
            importPhase = .importing
        }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let document = try parser.parse(data: data)
            let analyzed = analyzer.analyze(document)
            importError = nil
            analyzedGPX = analyzed
            importedGPXData = data
            stage = .routeImported
            importPhase = .imported
            let stats = analyzed.statistics
            addAssistant("路线已解析:\(document.name)。\(fmt(stats.distanceMeters / 1000)) km、爬升 \(Int(stats.ascentMeters)) m、质量 \(analyzed.qualityScore)/100。", card: .route)
        } catch {
            importError = error.localizedDescription
            importPhase = .failed
            addStatus("GPX 导入失败:\(error.localizedDescription)")
        }
    }

    /// 从历史记录预载路线,规划时无需再次导入 GPX 文件。
    func loadForPlanning(_ record: RouteRecord) {
        let analyzed = record.analyzed()
        analyzedGPX = analyzed
        importedGPXData = try? JSONEncoder().encode(record.document)
        importError = nil
        importPhase = .imported
    }

    func buildPlan(profile: FatigueProfile) -> PlanningResult? {
        guard let analyzedGPX, experience.isComplete else { return nil }
        var route = Route(analyzedGPX: analyzedGPX)
        let comparison = HikingRuleTools.compareToExperience(route: route, experience: experience)
        route.estimatedHours = comparison.estimatedHours
        let supply = HikingRuleTools.calculateSupplyBudget(route: route, profile: profile)
        let equipment = HikingRuleTools.buildEquipmentChecklist(route: route, supply: supply, qualityScore: analyzedGPX.qualityScore)
        stage = .ready
        addAssistant("已把这条路线和你的经验上限交叉比对,并按预计耗时给出补给与装备。", card: .report)
        return PlanningResult(route: route, comparison: comparison, supply: supply, equipment: equipment)
    }

    /// 行中请求健康授权并抓取快照。
    func requestHealthAuthorization() async -> HealthKitService.AuthorizationState {
        let state = await healthKit.requestAuthorization()
        healthSnapshot = await healthKit.fetchSnapshot()
        return state
    }

    func refreshHealthSnapshot() async {
        healthSnapshot = await healthKit.fetchSnapshot()
    }

    func refreshHealthAuthorizationState() async -> HealthKitService.AuthorizationState {
        await healthKit.refreshAuthorizationState()
    }

    private func addAssistant(_ text: String, card: ChatItem.Card? = nil) { chat.append(.init(role: .assistant, text: text, card: card)) }
    private func addUser(_ text: String) { chat.append(.init(role: .user, text: text)) }
    private func addStatus(_ text: String) { chat.append(.init(role: .status, text: text)) }
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}

struct PlanningResult {
    var route: Route
    var comparison: RouteComparison
    var supply: SupplyBudgetResult
    var equipment: [EquipmentItem]
}
