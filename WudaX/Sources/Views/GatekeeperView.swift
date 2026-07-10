import SwiftUI

// MARK: - 阶段二：出发前守门

struct GatekeeperView: View {
    @EnvironmentObject var session: TripSession
    @State private var checks: [GateItem] = [
        .init(icon: "flashlight.on.fill", title: "头灯", done: true),
        .init(icon: "battery.100", title: "备用电源", done: true),
        .init(icon: "cloud.rain", title: "保暖 / 雨具", done: false),
        .init(icon: "map", title: "离线轨迹", done: true)
    ]

    struct GateItem: Identifiable {
        let id = UUID()
        var icon: String
        var title: String
        var done = false
    }

    private var warnings: [String] { AgentEngine.gateWarnings(plan: session.plan) }
    private var allEquipDone: Bool { checks.allSatisfy(\.done) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("出发之前，确认身上真实的资源。")
                        .font(WDFont.body(14)).foregroundStyle(WDColor.mist)

                    checklist

                    if !warnings.isEmpty { warningCard }

                    actionRow

                    PillButton(
                        title: allEquipDone ? "接受风险并出发" : "先完成装备确认",
                        color: allEquipDone ? WDColor.ricePaper : WDColor.mossSurface,
                        textColor: allEquipDone ? WDColor.ink : WDColor.mist
                    ) {
                        if allEquipDone { session.depart() }
                    }
                    Text("Agent 将在行程中按时间、位置与风险节点主动与你确认状态。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(22)
            }
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
                supplyRow(icon: "drop.fill", title: "饮用水",
                          current: session.plan.waterL ?? 0, suggested: session.plan.suggestedWaterL,
                          unit: "L", fmt: { String(format: "%.1f", $0) })
                Divider().overlay(WDColor.mist.opacity(0.15)).padding(.vertical, 10)
                supplyRow(icon: "flame.fill", title: "食物",
                          current: session.plan.foodKcal ?? 0, suggested: session.plan.suggestedFoodKcal,
                          unit: "kcal", fmt: { String(Int($0)) })
                Divider().overlay(WDColor.mist.opacity(0.15)).padding(.vertical, 10)

                ForEach($checks) { $item in
                    Toggle(isOn: $item.done.animation(.spring(duration: 0.3))) {
                        Label(item.title, systemImage: item.icon)
                            .font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                    }
                    .toggleStyle(CheckToggleStyle())
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func supplyRow(icon: String, title: String, current: Double,
                           suggested: Double, unit: String, fmt: (Double) -> String) -> some View {
        let ok = current >= suggested
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                Spacer()
                Text("\(fmt(current)) / 建议 \(fmt(suggested)) \(unit)")
                    .font(WDFont.mono(13))
                    .foregroundStyle(ok ? WDColor.bamboo : WDColor.amber)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WDColor.mossSurface).frame(height: 5)
                    Capsule()
                        .fill(ok ? WDColor.bamboo : WDColor.amber)
                        .frame(width: geo.size.width * min(current / suggested, 1), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    private var warningCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("出发前提醒", systemImage: "exclamationmark.triangle.fill")
                    .font(WDFont.heading(15)).foregroundStyle(WDColor.amber)
                ForEach(warnings, id: \.self) { w in
                    Text("· \(w)").font(WDFont.body(13.5)).foregroundStyle(WDColor.ricePaper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("你计划路线后半程有长下坡，且预计 17:40 后仍可能在复杂地形。")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(WDColor.amber.opacity(0.4), lineWidth: 1)
        )
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            GhostButton(title: "增加补给", color: WDColor.amber) {
                withAnimation {
                    session.plan.waterL = session.plan.suggestedWaterL
                    session.plan.foodKcal = max(session.plan.foodKcal ?? 0, session.plan.suggestedFoodKcal)
                }
                Haptics.tap()
            }
            GhostButton(title: "降低路线目标") {
                withAnimation {
                    session.plan.suggestedWaterL = 2.0
                    session.plan.suggestedFoodKcal = 1200
                    session.plan.riskLevel = .medium
                }
                Haptics.tap()
            }
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
