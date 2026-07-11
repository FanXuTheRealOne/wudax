import SwiftUI
import MapKit

// MARK: - 阶段三：行中仪表 + Agent 主动问询

struct TripDashboardView: View {
    @EnvironmentObject var session: TripSession

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        progressCard
                        routeMatchingCard
                        if let d = session.lastDecision { verdictCard(d) }
                        if let document = session.planning.analyzedGPX?.document { routeMapCard(document) }
                        resourceCard
                        if !session.events.isEmpty { eventCard }
                        watchPreview
                        GhostButton(title: "结束行程", color: WDColor.mist) {
                            session.endTrip(retreated: false)
                        }
                    }
                    .padding(22)
                }
            }
            .blur(radius: session.activeCheckin != nil ? 6 : 0)

            if let trigger = session.activeCheckin {
                CheckinCardView(trigger: trigger)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $session.showRetreatSheet) {
            RetreatDecisionView()
                .presentationDetents([.large])
                .presentationBackground(WDColor.inkPine)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Circle().fill(WDColor.bamboo).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(WDColor.bamboo.opacity(0.4), lineWidth: 5))
                Text("行程进行中")
                    .font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
                Spacer()
                Text("距日落 \(String(format: "%.1f", session.status.hoursToSunset)) h")
                    .font(WDFont.mono(13)).foregroundStyle(
                        session.status.hoursToSunset < 3 ? WDColor.amber : WDColor.mist)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
    }

    private var progressCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    StatChip(icon: "figure.hiking", label: "已行进",
                             value: String(format: "%.1f km", session.status.elapsedKm),
                             tint: WDColor.bamboo)
                    StatChip(icon: "clock", label: "计划偏差",
                             value: "\(session.status.planDeltaMin) min",
                             tint: session.status.planDeltaMin <= -30 ? WDColor.amber : WDColor.mist)
                    StatChip(icon: "drop", label: "剩余水量",
                             value: String(format: "%.1f L", session.status.remainingWaterL),
                             tint: session.status.remainingWaterL < 1 ? WDColor.amber : WDColor.mist)
                }
                ElevationProfileView(
                    points: session.plan.route.elevationProfile,
                    riskIndices: session.plan.route.riskPoints.map(\.profileIndex),
                    markerIndex: session.status.profileIndex,
                    markerColor: WDColor.bamboo,
                    height: 100
                )
                if session.status.upcomingLongDescent {
                    Label("前方进入连续长下坡", systemImage: "arrow.down.forward")
                        .font(WDFont.caption()).foregroundStyle(WDColor.amber)
                }
            }
        }
    }

    private var routeMatchingCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("GPX 路线匹配", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper)
                    Spacer()
                    Text(confidenceLabel(session.routeMatch?.confidence))
                        .font(WDFont.caption())
                        .foregroundStyle(confidenceTint(session.routeMatch))
                }

                if let match = session.routeMatch {
                    Text(routeStatusText(match))
                        .font(WDFont.body(15).weight(.medium))
                        .foregroundStyle(match.isOffRoute ? WDColor.amber : WDColor.ricePaper)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Label(String(format: "剩余 %.1f km", match.remainingDistanceMeters / 1_000),
                              systemImage: "flag.checkered")
                        Label("剩余爬升 \(Int(match.remainingAscentMeters.rounded())) m",
                              systemImage: "mountain.2")
                    }
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)

                    if let waypoint = match.nextWaypoint,
                       let distance = match.distanceToNextWaypointMeters {
                        Label("下一航点：\(waypoint.name ?? "未命名航点") · \(Int(distance.rounded())) m",
                              systemImage: "mappin.and.ellipse")
                            .font(WDFont.caption(11)).foregroundStyle(WDColor.bamboo)
                    }

                    if match.isOffRoute {
                        Label("估计距计划路线 \(Int(match.distanceToRouteMeters.rounded())) m",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(WDFont.body(13).weight(.semibold)).foregroundStyle(WDColor.amber)
                    }
                    Text(match.reason)
                        .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                } else {
                    Text("等待第一个可用 GPS 定位，路线已在本地准备。")
                        .font(WDFont.body(14)).foregroundStyle(WDColor.mist)
                }
            }
        }
    }

    private func routeStatusText(_ match: RouteMatchResult) -> String {
        switch match.confidence {
        case .high:
            return String(format: "位于路线第 %.1f km，距终点 %.1f km",
                          match.routeProgressMeters / 1_000, match.remainingDistanceMeters / 1_000)
        case .medium:
            if let start = match.progressRangeStartMeters, let end = match.progressRangeEndMeters {
                return String(format: "估计位于路线第 %.1f–%.1f km", start / 1_000, end / 1_000)
            }
            return String(format: "大致位于路线第 %.1f km，定位仍在连续校验",
                          match.routeProgressMeters / 1_000)
        case .low:
            return "定位不稳定，请在下一个明显路标确认位置"
        case .none:
            return "暂无法确认路线位置，显示最后可信位置"
        }
    }

    private func confidenceLabel(_ confidence: RouteMatchConfidence?) -> String {
        switch confidence {
        case .some(.high): "高置信"
        case .some(.medium): "中置信"
        case .some(.low): "低置信"
        case .some(.none): "无置信"
        case nil: "等待定位"
        }
    }

    private func confidenceTint(_ match: RouteMatchResult?) -> Color {
        guard let match else { return WDColor.mist }
        if match.isOffRoute { return WDColor.amber }
        switch match.confidence {
        case .high: return WDColor.bamboo
        case .medium: return WDColor.ricePaper
        case .low, .none: return WDColor.amber
        }
    }

    private func verdictCard(_ d: AgentDecision) -> some View {
        InkCard {
            HStack(spacing: 14) {
                SealBadge(text: d.verdict.rawValue, color: d.verdict.color,
                          size: d.verdict.rawValue.count > 2 ? 64 : 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("上次确认结论").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    Text(d.reasons.first ?? "").font(WDFont.body(13.5))
                        .foregroundStyle(WDColor.ricePaper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var resourceCard: some View {
        InkCard {
            HStack(spacing: 10) {
                Image(systemName: session.location.isMonitoring ? "location.fill" : "location.slash")
                    .foregroundStyle(session.location.isMonitoring ? WDColor.bamboo : WDColor.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.offlineResources.status.mode.rawValue)
                        .font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
                    Text(session.location.isMonitoring ? "GPS、路线匹配与偏航判断均在本机持续运行" : "定位未持续更新；状态判断会降低可信度")
                        .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                }
                Spacer()
            }
        }
    }

    private func routeMapCard(_ document: GPXDocument) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("实时路线", systemImage: "map")
                        .font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper)
                    Spacer()
                    Text("GPS \(session.location.isMonitoring ? "已连接" : "等待授权")")
                        .font(WDFont.caption()).foregroundStyle(session.location.isMonitoring ? WDColor.bamboo : WDColor.amber)
                }
                RouteMapView(
                    points: document.points,
                    currentCoordinate: session.location.latestLocation?.coordinate,
                    matchedCoordinate: session.routeMatch?.matchedCoordinate,
                    horizontalAccuracyMeters: session.location.latestLocation?.horizontalAccuracy,
                    matchConfidence: session.routeMatch?.confidence,
                    isOffRoute: session.routeMatch?.isOffRoute ?? false
                )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("路线线条、候选段匹配和偏航判断来自本地 GPX；无地图瓦片时仍可工作。")
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
            }
        }
    }

    private var eventCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("主动事件", systemImage: "bell.badge")
                    .font(WDFont.heading(15)).foregroundStyle(WDColor.amber)
                ForEach(session.events.suffix(3)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(event.risk.color).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(WDFont.body(13.5)).foregroundStyle(WDColor.ricePaper)
                            Text(event.detail).font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // 手表端预览（PRD：手表优先承接行中交互）
    private var watchPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手表端同步").font(WDFont.caption()).foregroundStyle(WDColor.mist)
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("wudaX").font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundStyle(WDColor.mist)
                    Text(session.lastDecision?.watchHint ?? "状态良好，按计划继续。")
                        .font(WDFont.body(12).weight(.medium))
                        .foregroundStyle(WDColor.onDark)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    HStack(spacing: 6) {
                        Circle().fill(WDColor.bamboo).frame(width: 5, height: 5)
                        Circle().fill(WDColor.mist.opacity(0.3)).frame(width: 5, height: 5)
                        Circle().fill(WDColor.mist.opacity(0.3)).frame(width: 5, height: 5)
                    }
                }
                .padding(16)
                .frame(width: 165, height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: 32)
                            .stroke(WDColor.mossSurface, lineWidth: 3))
                )
                Spacer()
            }
        }
    }
}

// MARK: - 状态三问卡片

struct CheckinCardView: View {
    @EnvironmentObject var session: TripSession
    let trigger: CheckinTrigger

    @State private var water: Double = 1.5
    @State private var knee: Double = 0
    @State private var drowsy: Double = 0

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Circle().fill(WDColor.amber).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trigger.rawValue)
                            .font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
                        Text(trigger.explanation)
                            .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("剩余水量").font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                        Spacer()
                        Text(String(format: "%.1f L", water))
                            .font(WDFont.mono(20))
                            .foregroundStyle(water < 1 ? WDColor.amber : WDColor.bamboo)
                            .contentTransition(.numericText())
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<6) { i in
                            let v = Double(i) * 0.5
                            Button {
                                withAnimation(.spring(duration: 0.25)) { water = v }
                                Haptics.tap()
                            } label: {
                                Image(systemName: water >= v && v > 0 ? "drop.fill" : "drop")
                                    .font(.system(size: 22))
                                    .foregroundStyle(water >= v && v > 0 ? WDColor.bamboo : WDColor.mist.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                ScaleQuestion(title: "膝盖疼痛", lowLabel: "无感", highLabel: "无法行走",
                              value: $knee, warnThreshold: 4)
                ScaleQuestion(title: "困倦程度", lowLabel: "清醒", highLabel: "睁不开眼",
                              value: $drowsy, warnThreshold: 5)

                PillButton(title: "提交状态") {
                    session.submitCheckin(water: water, knee: knee, drowsy: drowsy)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(WDColor.deepMoss)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(WDColor.amber.opacity(0.35), lineWidth: 1)
            )
            .padding(16)
        }
        .onAppear { water = min(session.status.remainingWaterL, 2.5) }
    }
}
