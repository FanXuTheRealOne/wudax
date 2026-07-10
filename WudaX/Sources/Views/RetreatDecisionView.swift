import SwiftUI

// MARK: - 阶段四：撤退窗口判断

struct RetreatDecisionView: View {
    @EnvironmentObject var session: TripSession
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    private var decision: AgentDecision {
        session.lastDecision ?? AgentDecision(
            verdict: .downgrade, reasons: [], watchHint: "", detail: "")
    }

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            ContourBackground(opacity: 0.04).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Capsule().fill(WDColor.mist.opacity(0.4))
                        .frame(width: 40, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                    HStack(spacing: 18) {
                        SealBadge(text: decision.verdict.rawValue,
                                  color: decision.verdict.color, size: 96)
                            .scaleEffect(appeared ? 1 : 0.5)
                            .opacity(appeared ? 1 : 0)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("撤退窗口")
                                .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                            Text("你还未越过不可逆点")
                                .font(WDFont.heading(19)).foregroundStyle(WDColor.ricePaper)
                            Text("现在决定，仍有余量。")
                                .font(WDFont.body(13)).foregroundStyle(WDColor.mist)
                        }
                    }

                    // 触发原因
                    InkCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("触发原因").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                            ForEach(decision.reasons, id: \.self) { r in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(decision.verdict.color)
                                        .frame(width: 6, height: 6).padding(.top, 6)
                                    Text(r).font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    // 不可逆点剖面
                    InkCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("不可逆点 · 越过后只能走完全程")
                                .font(WDFont.caption()).foregroundStyle(WDColor.cinnabar)
                            ElevationProfileView(
                                points: session.plan.route.elevationProfile,
                                riskIndices: session.plan.route.riskPoints.map(\.profileIndex),
                                markerIndex: min(session.status.profileIndex + 2,
                                                 session.plan.route.elevationProfile.count - 1),
                                markerColor: WDColor.cinnabar,
                                height: 100
                            )
                        }
                    }

                    // 两个选项对比
                    HStack(spacing: 12) {
                        optionCard(
                            title: "当前节点下撤",
                            lines: ["2.1 km 到公路", "日落前可完成", "风险可控"],
                            tint: WDColor.bamboo, recommended: true)
                        optionCard(
                            title: "继续至发云界",
                            lines: ["剩余 6.8 km", "回程夜间下撤", "风险高"],
                            tint: WDColor.cinnabar, recommended: false)
                    }

                    Text(decision.detail)
                        .font(WDFont.body(13.5)).foregroundStyle(WDColor.mist)
                        .fixedSize(horizontal: false, vertical: true)

                    PillButton(title: "选择下撤路线", color: decision.verdict.color, textColor: .white) {
                        session.endTrip(retreated: true)
                    }
                    GhostButton(title: "仍然继续（自行承担）") {
                        dismiss()
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 22)
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.7).delay(0.2)) { appeared = true } }
    }

    private func optionCard(title: String, lines: [String], tint: Color, recommended: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(WDFont.body(14).weight(.semibold))
                    .foregroundStyle(WDColor.ricePaper)
                    .minimumScaleFactor(0.8).lineLimit(1)
                Spacer()
            }
            ForEach(lines, id: \.self) { l in
                Text("· \(l)").font(WDFont.caption()).foregroundStyle(WDColor.mist)
            }
            if recommended {
                Text("建议")
                    .font(WDFont.caption(11).weight(.semibold)).foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().stroke(tint, lineWidth: 1))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(WDColor.deepMoss)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(recommended ? tint.opacity(0.6) : .clear, lineWidth: 1.2))
        )
    }
}
