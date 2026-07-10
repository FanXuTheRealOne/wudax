import SwiftUI

// MARK: - 阶段一产出：行程预算卡

struct BudgetCardView: View {
    @EnvironmentObject var session: TripSession
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    riskHeader
                    profileCard
                    risksCard
                    suppliesCard
                    checkpointsCard
                    Spacer(minLength: 8)
                    PillButton(title: "确认并开始准备") { session.confirmBudget() }
                }
                .padding(22)
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.8).delay(0.1)) { appeared = true } }
    }

    private var topBar: some View {
        HStack {
            Button { session.phase = .planningChat } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Text("行程预算卡").font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Color.clear.frame(width: 17, height: 17)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var riskHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.plan.route.name)
                    .font(WDFont.heading(20)).foregroundStyle(WDColor.ricePaper)
                if let dep = session.plan.departureTime {
                    Text("\(dep, format: .dateTime.hour().minute()) 出发 · 日落 19:12")
                        .font(WDFont.mono(13)).foregroundStyle(WDColor.mist)
                }
                Text("总风险等级")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    .padding(.top, 6)
            }
            Spacer()
            SealBadge(text: session.plan.riskLevel.rawValue,
                      color: session.plan.riskLevel.color, size: 84)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
        }
    }

    private var profileCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("海拔剖面 · 3 个风险点")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                ElevationProfileView(
                    points: session.plan.route.elevationProfile,
                    riskIndices: session.plan.route.riskPoints.map(\.profileIndex)
                )
                ForEach(session.plan.route.riskPoints) { rp in
                    HStack(spacing: 8) {
                        Circle().fill(WDColor.amber).frame(width: 6, height: 6)
                        Text(rp.title).font(WDFont.body(13).weight(.medium))
                            .foregroundStyle(WDColor.ricePaper)
                        Text(rp.detail).font(WDFont.caption())
                            .foregroundStyle(WDColor.mist)
                        Spacer()
                    }
                }
            }
        }
    }

    private var risksCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("最需要警惕的 3 件事", systemImage: "exclamationmark.triangle")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.amber)
                ForEach(Array(session.plan.topRisks.enumerated()), id: \.offset) { i, risk in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(WDFont.mono(13)).foregroundStyle(WDColor.amber)
                            .frame(width: 22, height: 22)
                            .background(Circle().stroke(WDColor.amber.opacity(0.5), lineWidth: 1))
                        Text(risk).font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var suppliesCard: some View {
        InkCard(light: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("建议补给与装备")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ink)
                HStack(spacing: 10) {
                    supplyChip("drop.fill", "水", "≥ \(String(format: "%.1f", session.plan.suggestedWaterL)) L",
                               enough: (session.plan.waterL ?? 0) >= session.plan.suggestedWaterL)
                    supplyChip("flame.fill", "食物", "≥ \(Int(session.plan.suggestedFoodKcal)) kcal",
                               enough: (session.plan.foodKcal ?? 0) >= session.plan.suggestedFoodKcal)
                    supplyChip("flashlight.on.fill", "头灯", "必带", enough: true)
                }
                if let w = session.plan.waterL, w < session.plan.suggestedWaterL {
                    Text("你计划携带 \(String(format: "%.1f", w)) L，低于建议下限，出发前会再次确认。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.amber)
                }
            }
        }
    }

    private func supplyChip(_ icon: String, _ name: String, _ req: String, enough: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(enough ? WDColor.bamboo : WDColor.amber)
            Text(name).font(WDFont.caption(11)).foregroundStyle(WDColor.ink.opacity(0.6))
            Text(req).font(WDFont.mono(12)).foregroundStyle(WDColor.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(WDColor.ink.opacity(0.05)))
    }

    private var checkpointsCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("关键复核点", systemImage: "mappin.and.ellipse")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                ForEach(Array(session.plan.checkpoints.enumerated()), id: \.offset) { _, cp in
                    HStack(spacing: 10) {
                        Image(systemName: "flag")
                            .font(.system(size: 12)).foregroundStyle(WDColor.bamboo)
                        Text(cp).font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                Text("到达每个复核点时，我会主动和你确认状态。")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
            }
        }
    }
}
