import Foundation
import UserNotifications
import Combine

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationGranted = false
    private var lastNotificationAt: Date?
    private var lastRisk: RiskLevel = .low
    private var lastRouteDeviationNotificationAt: Date?

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            authorizationGranted = granted
            return granted
        } catch {
            authorizationGranted = false
            return false
        }
    }

    func postIfNeeded(risk: RiskEvaluation, action: ActionRecommendation, now: Date = Date()) {
        guard authorizationGranted else { return }
        let escalated = risk.level.rank > lastRisk.rank
        let cooledDown = lastNotificationAt.map { now.timeIntervalSince($0) >= 30 * 60 } ?? true
        guard escalated || cooledDown else { return }
        lastNotificationAt = now
        lastRisk = risk.level
        let content = UNMutableNotificationContent()
        content.title = "WUDAX · \(action.title)"
        content.body = action.detail
        content.sound = risk.level == .high ? .defaultCritical : .default
        let request = UNNotificationRequest(identifier: "wudax-risk-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func postRouteDeviationIfNeeded(_ result: RouteMatchResult, now: Date = Date()) {
        guard authorizationGranted, result.isOffRoute else { return }
        let cooledDown = lastRouteDeviationNotificationAt.map {
            now.timeIntervalSince($0) >= 15 * 60
        } ?? true
        guard cooledDown else { return }
        lastRouteDeviationNotificationAt = now

        let content = UNMutableNotificationContent()
        content.title = "WUDAX · 可能偏离计划路线"
        content.body = "距计划路线约 \(Int(result.distanceToRouteMeters.rounded())) 米。请停下确认方向、明显路标和退路。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "wudax-off-route-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private extension RiskLevel {
    var rank: Int {
        switch self { case .low: 0; case .medium: 1; case .mediumHigh: 2; case .high: 3 }
    }
}
