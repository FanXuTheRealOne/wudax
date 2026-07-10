import Foundation
import Combine

@MainActor
final class PlanningCoordinator: ObservableObject {
    enum Stage: Equatable {
        case idle, requestingHealth, collecting, routeImported, ready
    }

    struct ChatItem: Identifiable, Equatable {
        let id = UUID()
        var role: Role
        var text: String
        var card: Card?

        enum Role: Equatable { case assistant, user, status }
        enum Card: Equatable {
            case health
            case healthHistory
            case questionnaire
            case route
            case report
            case supplies
            case equipment
        }
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var healthSnapshot: HealthSnapshot?
    @Published private(set) var analyzedGPX: AnalyzedGPX?
    @Published private(set) var importedGPXData: Data?
    @Published private(set) var chat: [ChatItem] = []
    @Published var importError: String?
    @Published var subjective: [String: Double] = [:]
    @Published var personalHealth = PersonalHealthProfile()

    /// Route import is a Stage 1 action and stays available while the health
    /// history card is still collecting answers.
    var canImportGPX: Bool {
        switch stage {
        case .requestingHealth, .collecting, .routeImported, .ready:
            return true
        case .idle, .requestingHealth:
            return false
        }
    }

    let healthKit = HealthKitService()
    private let parser = GPXParser()
    private let analyzer = GPXAnalyzer()

    func reset() {
        stage = .idle
        healthSnapshot = nil
        analyzedGPX = nil
        importedGPXData = nil
        chat = []
        importError = nil
        subjective = [:]
        personalHealth = PersonalHealthProfile()
    }

    func begin() async {
        guard stage == .idle else { return }
        stage = .requestingHealth
        addAssistant("我先读取这次徒步真正有用的身体数据。没有授权或暂无数据时，我会直接标出来，再用几个问题补齐。", card: .health)
        // Give SwiftUI one turn to finish presenting the planning screen before
        // asking HealthKit to present its system permission sheet.
        await Task.yield()
        let state = await requestHealthAuthorization()
        stage = .collecting
        if state == .granted {
            let count = healthSnapshot?.readings.count ?? 0
            addStatus("已读取 \(count) 项 HealthKit 数据；每个数值都保留采样时间。")
        } else {
            addStatus("HealthKit 未提供数据。你仍可继续，准备度会按问卷和路线信息计算。")
        }
        addAssistant("在导入路线前，我需要了解几项个人健康史：当前或近期伤病、既往手术恢复情况，以及是否有慢性病、个人药物或医生限制。", card: .healthHistory)
    }

    /// Re-run the system authorization request from the visible HealthKit card.
    /// iOS shows the sheet when permission is undetermined and safely returns
    /// the current state after the user has already answered it.
    func requestHealthAuthorization() async -> HealthKitService.AuthorizationState {
        let state = await healthKit.requestAuthorization()
        healthSnapshot = await healthKit.fetchSnapshot()
        return state
    }

    func importGPX(from url: URL) {
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
            let stats = analyzed.statistics
            addAssistant("路线已解析：\(document.name)。\(String(format: "%.1f", stats.distanceMeters / 1000)) km，爬升 \(Int(stats.ascentMeters)) m，质量 \(analyzed.qualityScore)/100。", card: .route)
            if !analyzed.qualityIssues.isEmpty {
                addStatus(analyzed.qualityIssues.map(\.message).joined(separator: "；"))
            }
            addAssistant("最后还需要几个只和今天有关的问题：最近睡眠、主观疲劳和疼痛。", card: .questionnaire)
        } catch {
            importError = error.localizedDescription
            addStatus("GPX 导入失败：\(error.localizedDescription)")
        }
    }

    func answerInjury(_ value: InjuryLocation) {
        personalHealth.injury = value
        addUser("当前或近期伤病：\(value.rawValue)")
    }

    func answerSurgery(_ value: SurgeryHistory) {
        personalHealth.surgery = value
        if value == .none { personalHealth.surgeryLocation = nil }
        addUser("手术史：\(value.rawValue)")
    }

    func answerSurgeryLocation(_ value: SurgeryLocation) {
        personalHealth.surgeryLocation = value
        addUser("既往手术部位：\(value.rawValue)")
    }

    func answerMedicalConsideration(_ value: MedicalConsideration) {
        let wasComplete = personalHealth.isComplete
        personalHealth.medicalConsideration = value
        addUser("需要特别注意的情况：\(value.rawValue)")
        if !wasComplete && personalHealth.isComplete {
            addAssistant("个人健康情况已记录。现在请导入本次路线 GPX，我会检查轨迹、海拔、时间间隔和异常点。", card: .route)
        }
    }

    func answerSleep(_ hours: Double) { subjective["sleepHours"] = hours; addUser("最近睡眠约 \(String(format: "%.1f", hours)) 小时") }
    func answerFatigue(_ score: Double) { subjective["fatigue"] = score; addUser("主观疲劳 \(Int(score))/10") }
    func answerPain(_ score: Double) { subjective["pain"] = score; addUser("当前疼痛 \(Int(score))/10") }

    func buildPlan(profile: FatigueProfile) -> PlanningResult? {
        guard let analyzedGPX, personalHealth.isComplete else { return nil }
        let route = Route(analyzedGPX: analyzedGPX)
        let readiness = HikingRuleTools.calculateUserReadiness(snapshot: healthSnapshot,
                                                               subjective: subjective,
                                                               personalHealth: personalHealth)
        let load = HikingRuleTools.calculateRouteLoad(route: route)
        let gap = HikingRuleTools.calculateChallengeGap(route: route, profile: profile, readiness: readiness)
        let supply = HikingRuleTools.calculateSupplyBudget(route: route, profile: profile)
        let equipment = HikingRuleTools.buildEquipmentChecklist(route: route, supply: supply, qualityScore: analyzedGPX.qualityScore)
        stage = .ready
        addAssistant("我把路线负荷、今天的准备度和个人下坡耐受合在一起了。下面这张报告卡会说明哪些是数据、哪些是保守判断。", card: .report)
        return PlanningResult(route: route, readiness: readiness, load: load, gap: gap, supply: supply, equipment: equipment)
    }

    private func addAssistant(_ text: String, card: ChatItem.Card? = nil) { chat.append(.init(role: .assistant, text: text, card: card)) }
    private func addUser(_ text: String) { chat.append(.init(role: .user, text: text)) }
    private func addStatus(_ text: String) { chat.append(.init(role: .status, text: text)) }
}

struct PlanningResult {
    var route: Route
    var readiness: ReadinessResult
    var load: RouteLoadResult
    var gap: ChallengeGapResult
    var supply: SupplyBudgetResult
    var equipment: [EquipmentItem]
}
