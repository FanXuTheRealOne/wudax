import SwiftUI

// MARK: - 阶段一产出:行前报告(match report + 装备确认合并页)
// 看完「本次路线 × 过往经历」的比对报告,在同一页勾完装备与权限,直接出发。

struct GatekeeperReadiness: Equatable {
    enum Notice: Hashable {
        case offlineResources
        case locationPermission
        case notificationPermission
    }

    let offlineResourcesReady: Bool
    let locationAuthorized: Bool
    let notificationsAuthorized: Bool

    var notices: [Notice] {
        var result: [Notice] = []
        if !offlineResourcesReady { result.append(.offlineResources) }
        if !locationAuthorized { result.append(.locationPermission) }
        if !notificationsAuthorized { result.append(.notificationPermission) }
        return result
    }
}

struct BudgetCardView: View {
    @EnvironmentObject var session: TripSession
    @State private var appeared = false
    @State private var checks: [GateItem] = []
    @State private var readinessRevision = 0

    struct GateItem: Identifiable {
        let id = UUID()
        var title: String
        var reason: String
        var required: Bool
        var done = false
    }

    private var comparison: RouteComparison? { session.planningResult?.comparison }
    private var supply: SupplyBudgetResult? { session.planningResult?.supply }
    private var exp: HikerExperience { session.planning.experience }
    private var route: Route { session.plan.route }

    private var allRequiredDone: Bool { checks.filter(\.required).allSatisfy(\.done) }
    private var completedCheckCount: Int { checks.filter(\.done).count }
    private var allChecksDone: Bool { !checks.isEmpty && checks.allSatisfy(\.done) }
    private var locationReady: Bool {
        session.location.authorizationState == .whenInUse || session.location.authorizationState == .always
    }
    private var readiness: GatekeeperReadiness {
        GatekeeperReadiness(
            offlineResourcesReady: session.offlineResources.status.isReady,
            locationAuthorized: locationReady,
            notificationsAuthorized: session.notifications.authorizationGranted
        )
    }
    private var gateReady: Bool {
        allRequiredDone && readiness.notices.isEmpty
    }

    var body: some View {
        let _ = readinessRevision
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    riskHeader
                    comparisonCard
                    profileCard
                    analysisCard
                    suppliesCard
                    equipmentChecklist
                    checkpointsCard
                    if !readiness.notices.isEmpty {
                        permissionCard
                    }
                    Spacer(minLength: 8)
                    PillButton(
                        title: gateReady ? "接受风险并出发" : "先确认补给与装备清单",
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
        .onAppear {
            withAnimation(.spring(duration: 0.8).delay(0.1)) { appeared = true }
            if checks.isEmpty { rebuildChecks() }
        }
        .onReceive(session.location.objectWillChange) { _ in
            readinessRevision &+= 1
        }
        .onReceive(session.notifications.objectWillChange) { _ in
            readinessRevision &+= 1
        }
        .onReceive(session.offlineResources.objectWillChange) { _ in
            readinessRevision &+= 1
        }
    }

    private func rebuildChecks() {
        checks = session.plan.equipment.map {
            GateItem(title: $0.title, reason: $0.reason, required: $0.required)
        }
    }

    private func confirmAllChecks() {
        Haptics.tap()
        withAnimation(.spring(duration: 0.28)) {
            checks.markAllDone()
        }
    }

    private var topBar: some View {
        HStack {
            Button { session.phase = .planningChat } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Text("行前报告").font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Color.clear.frame(width: 17, height: 17)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var riskHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(route.name)
                    .font(WDFont.heading(20)).foregroundStyle(WDColor.ricePaper)
                Text(comparison?.difficultyLabel ?? session.plan.challengeGapLabel)
                    .font(WDFont.body(13).weight(.medium)).foregroundStyle(session.plan.riskLevel.color)
                if let c = comparison {
                    Text("为你预估耗时约 \(String(format: "%.1f", c.estimatedHours)) 小时\(c.isOvernight ? " · 需过夜(重装)" : " · 单日")")
                        .font(WDFont.mono(12)).foregroundStyle(WDColor.mist)
                }
            }
            Spacer()
            SealBadge(text: session.plan.riskLevel.rawValue,
                      color: session.plan.riskLevel.color, size: 84)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
        }
    }

    // 本次 × 你走过最难 —— 可视化对比
    private var comparisonCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("本次 × 你走过最难", systemImage: "arrow.left.and.right")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                compareRow("距离", cur: route.distanceKm, ref: exp.hardestDistanceKm, unit: "km")
                compareRow("累计拔高", cur: route.ascentM, ref: exp.hardestAscentM, unit: "m")
                compareRow("最高海拔", cur: route.elevationProfile.max() ?? 0, ref: exp.highestAltitudeM, unit: "m")
                Text("绿色=你走过最难的一次;琥珀=本次。超过基准即为新挑战。")
                    .font(WDFont.caption(10)).foregroundStyle(WDColor.mist.opacity(0.8))
            }
        }
    }

    private func compareRow(_ label: String, cur: Double, ref: Double, unit: String) -> some View {
        let ratio = ref > 0 ? cur / ref : 1
        let over = ratio > 1.02
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(WDFont.body(13)).foregroundStyle(WDColor.ricePaper)
                Spacer()
                Text("\(fmt(cur, unit)) / 历史 \(fmt(ref, unit))")
                    .font(WDFont.mono(12)).foregroundStyle(over ? WDColor.amber : WDColor.bamboo)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let refFrac = 0.62                       // 基准固定占 62%
                let curFrac = min(ratio * refFrac, 1.0)
                ZStack(alignment: .leading) {
                    Capsule().fill(WDColor.mossSurface).frame(height: 8)
                    Capsule().fill(WDColor.bamboo.opacity(0.5)).frame(width: w * refFrac, height: 8)
                    Capsule().fill(over ? WDColor.amber : WDColor.bamboo).frame(width: w * curFrac, height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private var profileCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("海拔剖面 · 关键风险点")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                ElevationProfileView(
                    points: route.elevationProfile,
                    riskIndices: route.riskPoints.map(\.profileIndex)
                )
                ForEach(route.riskPoints) { rp in
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

    private var analysisCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("为什么是「\(session.plan.riskLevel.rawValue)」风险", systemImage: "exclamationmark.triangle")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.amber)
                ForEach(Array((comparison?.analysis ?? session.plan.topRisks).enumerated()), id: \.offset) { i, risk in
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
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("补给方案", systemImage: "fork.knife")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                HStack(spacing: 10) {
                    supplyChip("drop.fill", "水", "≥ \(fmt(session.plan.suggestedWaterL, "L"))")
                    supplyChip("bolt.heart", "电解质", supply.map { fmt($0.electrolyteLiters, "L") } ?? "—")
                    supplyChip("flame.fill", "食物", "\(supply?.mealsCount ?? 0) 餐")
                }
                if let s = supply {
                    Text(s.explanation).font(WDFont.caption()).foregroundStyle(WDColor.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func supplyChip(_ icon: String, _ name: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(WDColor.bamboo)
            Text(name).font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
            Text(value).font(WDFont.mono(12)).foregroundStyle(WDColor.ricePaper)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(WDColor.mossSurface))
    }

    // 装备清单:直接在报告页逐项勾选确认,不再单独一页。
    private var equipmentChecklist: some View {
        InkCard {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("补给与装备清单", systemImage: "backpack")
                            .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                        Text("出发之前，确认背包里真实带了这些。")
                            .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                    }
                    Spacer(minLength: 8)
                    Button {
                        confirmAllChecks()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: allChecksDone ? "checkmark.seal.fill" : "checkmark.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text(allChecksDone ? "已确认" : "一键确认")
                                .font(WDFont.caption(11).weight(.semibold))
                        }
                        .foregroundStyle(allChecksDone ? WDColor.bamboo : WDColor.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(allChecksDone ? WDColor.mossSurface : WDColor.mossSurface.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(allChecksDone ? WDColor.bamboo.opacity(0.26) : WDColor.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(allChecksDone)
                    .accessibilityLabel(allChecksDone ? "补给与装备清单已全部确认" : "一键确认补给与装备清单")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
                if !checks.isEmpty {
                    Text("\(completedCheckCount)/\(checks.count) 项已确认")
                        .font(WDFont.caption(10))
                        .foregroundStyle(WDColor.mist)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                }
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
                ForEach(readiness.notices, id: \.self) { notice in
                    switch notice {
                    case .offlineResources:
                        auditRow(title: "GPX / 路线资源", value: "未准备")
                    case .locationPermission:
                        auditRow(title: "定位", value: "请开启")
                    case .notificationPermission:
                        auditRow(title: "通知", value: "请开启")
                    }
                }
                if readiness.notices.contains(.offlineResources) {
                    Text(session.offlineResources.status.integrityMessage)
                        .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                }
            }
        }
    }

    private func auditRow(title: String, value: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(WDColor.amber)
            Text(title).font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Text(value).font(WDFont.caption()).foregroundStyle(WDColor.amber)
        }
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

    private func fmt(_ v: Double, _ unit: String) -> String {
        (v >= 100 ? "\(Int(v))" : String(format: "%.1f", v)) + " " + unit
    }
}

extension Array where Element == BudgetCardView.GateItem {
    mutating func markAllDone() {
        for index in indices {
            self[index].done = true
        }
    }
}
