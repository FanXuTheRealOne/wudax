import SwiftUI
import MapKit

// MARK: - 阶段三:实时行程页 —— 全屏大地图 + 常驻计时/剩余距离面板
// 出发后先引导前往路线起点(虚线),到达起点自动开始计时与记录;
// 记录中常驻显示计时、剩余公里、已行进,详情卡片收进 sheet。

struct TripDashboardView: View {
    @EnvironmentObject var session: TripSession
    @EnvironmentObject var agent: WudaXAgent
    @State private var cameraMode: RouteMapCameraMode = .automatic
    @State private var cameraRequestID = 0
    @State private var mapLayer: RouteMapLayer = .standard
    @State private var showDetailSheet = false
    @State private var showAgentSheet = false
    @State private var showEndConfirm = false
    @State private var locationRevision = 0
    @State private var pulsing = false

    private var routePoints: [GPXTrackPoint] {
        session.planning.analyzedGPX?.document.points ?? []
    }

    private var isToStart: Bool {
        if case .toStart = session.trackingState { return true }
        return false
    }

    var body: some View {
        // 显式订阅嵌套的 LocationService,让地图与面板随定位实时重绘。
        let _ = locationRevision
        ZStack {
            fullScreenMap

            VStack(spacing: 0) {
                statusPill
                    .padding(.top, 8)
                if let banner = agent.latestBanner {
                    agentBanner(banner)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: banner.id) {
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            if agent.latestBanner?.id == banner.id {
                                withAnimation(.easeOut(duration: 0.3)) { agent.latestBanner = nil }
                            }
                        }
                }
                Spacer()
                mapControls
                    .padding(.bottom, 10)
                bottomPanel
            }
            .padding(.horizontal, 16)
            .blur(radius: session.activeCheckin != nil ? 6 : 0)

            if let trigger = session.activeCheckin {
                CheckinCardView(trigger: trigger)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            TripDetailSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(WDColor.inkPine)
        }
        .sheet(isPresented: $showAgentSheet) {
            SessionAgentView()
                .presentationDetents([.medium, .large])
                .presentationBackground(WDColor.inkPine)
        }
        .sheet(isPresented: $session.showRetreatSheet) {
            RetreatDecisionView()
                .presentationDetents([.large])
                .presentationBackground(WDColor.inkPine)
        }
        .confirmationDialog("结束这次行程？", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("结束并生成复盘", role: .destructive) { session.endTrip(retreated: false) }
            Button("继续行程", role: .cancel) {}
        } message: {
            Text("结束后本次记录会保存到这条路线的行走记录里。")
        }
        .onAppear { pulsing = true }
        .onReceive(session.location.objectWillChange) { _ in
            locationRevision &+= 1
        }
    }

    // MARK: 全屏地图

    @ViewBuilder
    private var fullScreenMap: some View {
        if routePoints.count >= 2 {
            RouteMapView(
                points: routePoints,
                currentCoordinate: session.location.latestLocation?.coordinate,
                tracksUserLocation: true,
                userHeadingDegrees: session.location.headingDegrees,
                matchedCoordinate: session.routeMatch?.matchedCoordinate,
                matchConfidence: session.routeMatch?.confidence,
                isOffRoute: session.routeMatch?.isOffRoute ?? false,
                cameraMode: cameraMode,
                cameraRequestID: cameraRequestID,
                showsEndpointFlags: true,
                guideLineToStart: isToStart,
                mapLayer: mapLayer
            )
            .ignoresSafeArea()
        } else {
            ZStack {
                WDColor.inkPine.ignoresSafeArea()
                ContourBackground().ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "map")
                        .font(.system(size: 38, weight: .ultraLight)).foregroundStyle(WDColor.mist.opacity(0.5))
                    Text("本次行程没有加载 GPX 路线").font(WDFont.body(14)).foregroundStyle(WDColor.mist)
                }
            }
        }
    }

    // MARK: 顶部状态胶囊

    private var statusPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isToStart ? WDColor.amber : WDColor.bamboo)
                .frame(width: 9, height: 9)
                .overlay(
                    Circle()
                        .stroke((isToStart ? WDColor.amber : WDColor.bamboo).opacity(0.4), lineWidth: 5)
                        .scaleEffect(pulsing ? 1.6 : 0.9)
                        .opacity(pulsing ? 0 : 1)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)
                )
            Text(statusTitle)
                .font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Text("距日落 \(String(format: "%.1f", session.status.hoursToSunset)) h")
                .font(WDFont.mono(12)).foregroundStyle(
                    session.status.hoursToSunset < 3 ? WDColor.amber : WDColor.mist)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(
            Capsule().fill(WDColor.deepMoss.opacity(0.96))
                .overlay(Capsule().stroke(WDColor.line.opacity(0.7), lineWidth: 1))
                .shadow(color: WDColor.ink.opacity(0.10), radius: 12, y: 5)
        )
    }

    private var statusTitle: String {
        switch session.trackingState {
        case .waitingGPS: "等待 GPS 定位"
        case .toStart: "前往路线起点"
        case .recording: "行程进行中"
        }
    }

    // MARK: 地图相机控制

    private var mapControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                agentButton
                mapLayerMenu
                mapControlButton("arrow.up.left.and.arrow.down.right", selected: cameraMode == .route) {
                    cameraMode = .route
                    cameraRequestID += 1
                    Haptics.tap()
                }
                mapControlButton("location.fill", selected: cameraMode == .automatic) {
                    cameraMode = .automatic
                    cameraRequestID += 1
                    Haptics.tap()
                }
            }
        }
    }

    private var mapLayerMenu: some View {
        Menu {
            ForEach(RouteMapLayer.allCases) { layer in
                Button {
                    mapLayer = layer
                    Haptics.tap()
                } label: {
                    Label(layer.title, systemImage: layer.symbolName)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WDColor.ricePaper)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(WDColor.deepMoss.opacity(0.96))
                        .overlay(Circle().stroke(WDColor.line.opacity(0.8), lineWidth: 1))
                        .shadow(color: WDColor.ink.opacity(0.12), radius: 8, y: 4)
                )
        }
        .accessibilityLabel("切换地图图层，当前为\(mapLayer.title)")
    }

    /// 行中 AI 窗口入口:未读播报数角标。
    private var agentButton: some View {
        Button {
            showAgentSheet = true
            agent.markRead()
            Haptics.tap()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WDColor.onDark)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(WDColor.bamboo)
                        .shadow(color: WDColor.ink.opacity(0.16), radius: 8, y: 4)
                )
                .overlay(alignment: .topTrailing) {
                    if let unread = agent.activeContext?.unreadCount, unread > 0 {
                        Text("\(min(unread, 9))")
                            .font(WDFont.caption(10).weight(.bold)).foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(WDColor.cinnabar))
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// 主动播报浮条:点击进入 AI 窗口,8 秒后自动收起。
    private func agentBanner(_ message: AgentMessage) -> some View {
        Button {
            showAgentSheet = true
            agent.markRead()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(WDColor.amber)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    if let headline = message.signalHeadline {
                        Text(headline)
                            .font(WDFont.caption(10).weight(.semibold)).foregroundStyle(WDColor.amber)
                    }
                    Text(message.text)
                        .font(WDFont.body(13)).foregroundStyle(WDColor.ricePaper)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(WDColor.mist)
                    .padding(.top, 3)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(WDColor.deepMoss.opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WDColor.amber.opacity(0.4), lineWidth: 1))
                    .shadow(color: WDColor.ink.opacity(0.12), radius: 12, y: 5)
            )
        }
        .buttonStyle(.plain)
    }

    private func mapControlButton(_ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? WDColor.onDark : WDColor.ricePaper)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(selected ? WDColor.ink : WDColor.deepMoss.opacity(0.96))
                        .overlay(Circle().stroke(WDColor.line.opacity(selected ? 0 : 0.8), lineWidth: 1))
                        .shadow(color: WDColor.ink.opacity(0.12), radius: 8, y: 4)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部实时数据面板

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            switch session.trackingState {
            case .recording: recordingStats
            case .toStart(let distance): toStartStats(distance)
            case .waitingGPS: waitingStats
            }

            HStack(spacing: 10) {
                Button { showDetailSheet = true } label: {
                    Label("详情", systemImage: "list.bullet.rectangle")
                        .font(WDFont.body(15).weight(.medium))
                        .foregroundStyle(WDColor.ricePaper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14).stroke(WDColor.line, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button { showEndConfirm = true } label: {
                    Label("结束", systemImage: "xmark")
                        .font(WDFont.body(15).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14).fill(WDColor.cinnabar))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(WDColor.deepMoss.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(WDColor.line.opacity(0.7), lineWidth: 1))
                .shadow(color: WDColor.ink.opacity(0.14), radius: 18, y: 8)
        )
        .padding(.bottom, 8)
    }

    /// 记录中:计时 + 剩余公里 + 已行进,每秒刷新。
    private var recordingStats: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    bigStat(label: "计时", value: elapsedText(at: context.date), tint: WDColor.bamboo)
                    statDivider
                    bigStat(label: "剩余(km)", value: remainingKmText, tint: WDColor.ink)
                    statDivider
                    bigStat(label: "已行进(km)", value: String(format: "%.1f", session.status.elapsedKm), tint: WDColor.ink)
                }
                HStack(spacing: 12) {
                    smallStat("clock.badge.checkmark", "预计到达 \(etaText)")
                    if let match = session.routeMatch {
                        smallStat("mountain.2", "剩余爬升 \(Int(match.remainingAscentMeters.rounded())) m")
                    }
                    smallStat("antenna.radiowaves.left.and.right", gpsText,
                              tint: gpsTint)
                    Spacer()
                }
                if session.routeMatch?.isOffRoute == true {
                    Label("可能偏离路线,距路线约 \(Int((session.routeMatch?.distanceToRouteMeters ?? 0).rounded())) m",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(WDFont.caption(11).weight(.semibold)).foregroundStyle(WDColor.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// 未到起点:显示距起点距离与虚线引导提示。
    private func toStartStats(_ distanceMeters: Double) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(distanceText(distanceMeters))
                    .font(WDFont.mono(30)).foregroundStyle(WDColor.amber)
                    .contentTransition(.numericText())
                Text("距路线起点").font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
            }
            Rectangle().fill(WDColor.line).frame(width: 1, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Label("沿虚线走向起点旗标", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(WDFont.body(13).weight(.medium)).foregroundStyle(WDColor.ricePaper)
                Text("到达起点后自动开始计时与记录")
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                smallStat("antenna.radiowaves.left.and.right", gpsText, tint: gpsTint)
            }
            Spacer()
        }
    }

    private var waitingStats: some View {
        HStack(spacing: 12) {
            if session.location.accuracyAuthorization == .reducedAccuracy || isLocationCalibrating {
                Image(systemName: "location.slash.fill").foregroundStyle(WDColor.amber)
            } else {
                ProgressView().tint(WDColor.bamboo)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(waitingLocationTitle)
                    .font(WDFont.body(14).weight(.medium)).foregroundStyle(WDColor.ricePaper)
                Text(waitingLocationDetail)
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
            }
            Spacer()
        }
    }

    private func bigStat(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(WDFont.mono(24)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label).font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(WDColor.line).frame(width: 1, height: 38)
    }

    private func smallStat(_ icon: String, _ text: String, tint: Color = WDColor.mist) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint)
            Text(text).font(WDFont.caption(11)).foregroundStyle(tint)
        }
    }

    // MARK: 文案

    private func elapsedText(at now: Date) -> String {
        guard let start = session.hikeStartDate else { return "00:00:00" }
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private var remainingKmText: String {
        guard let remaining = session.remainingDistanceKm else { return "—" }
        return String(format: "%.2f", remaining)
    }

    private var etaText: String {
        guard let eta = session.estimatedFinishDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: eta)
    }

    private var gpsText: String {
        guard session.location.isMonitoring else { return "GPS 未连接" }
        guard let sample = session.location.latestRawLocation else { return "GPS 搜索中" }
        let age = Date().timeIntervalSince(sample.timestamp)
        guard age <= 15 else { return "GPS 数据已过期" }
        let accuracy = Int(sample.horizontalAccuracy.rounded())
        guard accuracy <= 100 else { return "GPS 校准中 · ±\(accuracy)m" }
        switch session.routeMatch?.confidence {
        case .some(.high): return "GPS ±\(accuracy)m · 高置信"
        case .some(.medium): return "GPS ±\(accuracy)m · 中置信"
        case .some(.low): return "GPS ±\(accuracy)m · 低置信"
        case .some(.none), nil: return "GPS ±\(accuracy)m"
        }
    }

    private var gpsTint: Color {
        guard session.location.isMonitoring,
              let sample = session.location.latestRawLocation,
              Date().timeIntervalSince(sample.timestamp) <= 15,
              sample.horizontalAccuracy <= 100 else { return WDColor.amber }
        return WDColor.bamboo
    }

    private var isLocationCalibrating: Bool {
        guard let sample = session.location.latestRawLocation else { return false }
        return sample.horizontalAccuracy > 100
    }

    private var waitingLocationTitle: String {
        if session.location.accuracyAuthorization == .reducedAccuracy {
            return "请在系统设置中开启精确位置"
        }
        if let sample = session.location.latestRawLocation,
           sample.horizontalAccuracy > 100 {
            return "定位精度不足 · ±\(Int(sample.horizontalAccuracy.rounded()))m"
        }
        return "等待第一个可靠 GPS 定位"
    }

    private var waitingLocationDetail: String {
        if session.location.accuracyAuthorization == .reducedAccuracy {
            return "关闭精确位置会明显降低路线匹配与偏航判断精度"
        }
        if isLocationCalibrating {
            return "请到开阔位置停留片刻；达到 100m 内才开始路线判断"
        }
        return "路线已在本地准备；定位后开始引导"
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1_000 ? String(format: "%.1f km", meters / 1_000) : "\(Int(meters.rounded())) m"
    }
}

// MARK: - 详情 sheet:海拔剖面 / 路线匹配 / 事件 / 资源 / 手表同步

private struct TripDetailSheet: View {
    @EnvironmentObject var session: TripSession

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("行程详情").font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
                    .padding(.top, 20)
                progressCard
                routeMatchingCard
                if let d = session.lastDecision { verdictCard(d) }
                resourceCard
                if !session.events.isEmpty { eventCard }
                watchPreview
                Spacer(minLength: 30)
            }
            .padding(22)
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
                        .fill(WDColor.nightSurface)
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
    @State private var supplyRatio: Double = 1.0
    @State private var fatigue: Double = 0

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

                Text("这是补充信息;心率、体能等会结合手表与外骨骼数据自动判断。")
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist.opacity(0.85))

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

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("剩余补给").font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                        Spacer()
                        Text("\(Int(supplyRatio * 100))%")
                            .font(WDFont.mono(20))
                            .foregroundStyle(supplyRatio < 0.35 ? WDColor.amber : WDColor.bamboo)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $supplyRatio, in: 0...1, step: 0.1)
                        .tint(supplyRatio < 0.35 ? WDColor.amber : WDColor.bamboo)
                    HStack {
                        Text("快吃完了").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                        Spacer()
                        Text("还很充足").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    }
                }

                ScaleQuestion(title: "主观疲劳", lowLabel: "轻松", highLabel: "精疲力竭",
                              value: $fatigue, warnThreshold: 5)

                PillButton(title: "提交状态") {
                    session.submitCheckin(fatigue: fatigue, water: water, supplyRatio: supplyRatio)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(WDColor.deepMoss)
                    .shadow(color: WDColor.ink.opacity(0.18), radius: 30, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(WDColor.amber.opacity(0.35), lineWidth: 1)
            )
            .padding(16)
        }
        .onAppear {
            water = min(session.status.remainingWaterL, 2.5)
            supplyRatio = session.status.remainingSupplyRatio
            fatigue = session.status.subjectiveFatigue
        }
    }
}
