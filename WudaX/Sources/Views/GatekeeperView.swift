import SwiftUI

// MARK: - 阶段二：出发守门（补给 + 装备清单确认，量化）

struct GatekeeperView: View {
    @EnvironmentObject var session: TripSession
    @State private var checks: [GateItem] = []

    struct GateItem: Identifiable {
        let id = UUID()
        var title: String
        var reason: String
        var required: Bool
        var done = false
    }

    private var allRequiredDone: Bool { checks.filter(\.required).allSatisfy(\.done) }
    private var locationReady: Bool {
        session.location.authorizationState == .whenInUse || session.location.authorizationState == .always
    }
    private var gateReady: Bool {
        allRequiredDone && locationReady && session.notifications.authorizationGranted && session.offlineResources.status.isReady
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("出发之前，逐项确认背包里真实带了这些。")
                        .font(WDFont.body(14)).foregroundStyle(WDColor.mist)

                    checklist
                    permissionCard

                    PillButton(
                        title: gateReady ? "接受风险并出发" : "先完成出发检查",
                        color: gateReady ? WDColor.ink : WDColor.mossSurface,
                        textColor: gateReady ? WDColor.onDark : WDColor.mist
                    ) {
                        if gateReady { session.depart() }
                    }
                    Text("Agent 将在行程中结合手表数据与你的确认，主动判断状态。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(22)
            }
        }
        .task {
            session.location.requestPermission()
            _ = await session.notifications.requestAuthorization()
        }
        .onAppear { if checks.isEmpty { rebuildChecks() } }
    }

    private func rebuildChecks() {
        checks = session.plan.equipment.map {
            GateItem(title: $0.title, reason: $0.reason, required: $0.required)
        }
    }

    private var topBar: some View {
        HStack {
            Button { session.phase = .budgetCard } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Text("出发守门").font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Color.clear.frame(width: 17, height: 17)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var checklist: some View {
        InkCard {
            VStack(spacing: 0) {
                Label("补给与装备清单", systemImage: "backpack")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                ForEach($checks) { $item in
                    Toggle(isOn: $item.done.animation(.spring(duration: 0.3))) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title).font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                                if !item.required {
                                    Text("可选").font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
                                }
                            }
                            Text(item.reason).font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                        }
                    }
                    .toggleStyle(CheckToggleStyle())
                    .padding(.vertical, 9)
                    if item.id != checks.last?.id {
                        Divider().overlay(WDColor.line)
                    }
                }
            }
        }
    }

    private var permissionCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("离线与权限", systemImage: "checklist")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                auditRow(title: "GPX / 路线资源", value: session.offlineResources.status.isReady ? "已就绪" : "未准备",
                         ok: session.offlineResources.status.isReady)
                auditRow(title: "定位", value: locationReady ? "已授权" : "等待授权", ok: locationReady)
                auditRow(title: "通知", value: session.notifications.authorizationGranted ? "已授权" : "等待授权",
                         ok: session.notifications.authorizationGranted)
                Text(session.offlineResources.status.integrityMessage)
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
            }
        }
    }

    private func auditRow(title: String, value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? WDColor.bamboo : WDColor.amber)
            Text(title).font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Text(value).font(WDFont.caption()).foregroundStyle(ok ? WDColor.bamboo : WDColor.amber)
        }
    }
}

struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle(); Haptics.tap() } label: {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(configuration.isOn ? WDColor.bamboo : WDColor.mist.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
    }
}
