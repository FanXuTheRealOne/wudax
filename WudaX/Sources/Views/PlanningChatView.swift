import SwiftUI
import UniformTypeIdentifiers

// MARK: - Stage 1：连续聊天式行前采集

struct PlanningChatView: View {
    @EnvironmentObject var session: TripSession
    @State private var showImporter = false
    @State private var answered: [(q: String, a: String)] = []
    @State private var showCurrent = false

    private var current: PlanQuestion? { session.plan.missingQuestions.first }
    private var hasRoute: Bool { session.planning.analyzedGPX != nil }
    private var subjectiveComplete: Bool {
        ["sleepHours", "fatigue", "pain"].allSatisfy { session.planning.subjective[$0] != nil }
    }
    private var canBuild: Bool { hasRoute && subjectiveComplete && session.plan.missingQuestions.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    chatStream
                    healthCard
                    routeCard
                    if hasRoute { subjectiveCard }
                    if hasRoute && subjectiveComplete { planQuestions }
                    if canBuild {
                        PillButton(title: "生成行前报告") { session.finalizePlanning() }
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 40)
                }
                .padding(22)
            }
        }
        .task { await session.planning.begin() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                session.planning.importGPX(from: url)
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.7).delay(0.3)) { showCurrent = true } }
    }

    private var topBar: some View {
        HStack {
            Button { session.phase = .home } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Text("行前计划").font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Text("离线").font(WDFont.caption()).foregroundStyle(WDColor.bamboo)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var chatStream: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(session.planning.chat) { item in
                HStack(alignment: .top, spacing: 9) {
                    if item.role == .assistant {
                        Circle().fill(WDColor.amber).frame(width: 7, height: 7).padding(.top, 6)
                    } else {
                        Color.clear.frame(width: 7, height: 7)
                    }
                    Text(item.text)
                        .font(WDFont.body(item.role == .status ? 12.5 : 14))
                        .foregroundStyle(item.role == .user ? WDColor.ink : WDColor.ricePaper)
                        .padding(.horizontal, item.role == .user ? 14 : 0)
                        .padding(.vertical, item.role == .user ? 9 : 0)
                        .background {
                            if item.role == .user { Capsule().fill(WDColor.ricePaper) }
                        }
                        .frame(maxWidth: .infinity, alignment: item.role == .user ? .trailing : .leading)
                }
            }
        }
    }

    private var healthCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("身体数据", systemImage: "heart.text.square")
                        .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                    Spacer()
                    Text(healthStatus).font(WDFont.caption()).foregroundStyle(healthTint)
                }
                Text(healthDetail)
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                if let snapshot = session.planning.healthSnapshot, !snapshot.readings.isEmpty {
                    HStack(spacing: 8) {
                        StatChip(icon: "bed.double", label: "睡眠", value: healthValue(.sleepDuration, suffix: " h"), tint: WDColor.bamboo)
                        StatChip(icon: "heart", label: "静息心率", value: healthValue(.restingHeartRate, suffix: " bpm"), tint: WDColor.amber)
                    }
                }
            }
        }
    }

    private var routeCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("本次 GPX 路线", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                if let analyzed = session.planning.analyzedGPX {
                    let stats = analyzed.statistics
                    HStack(spacing: 8) {
                        StatChip(icon: "location", label: "距离", value: String(format: "%.1f km", stats.distanceMeters / 1000), tint: WDColor.bamboo)
                        StatChip(icon: "mountain.2", label: "爬升", value: "\(Int(stats.ascentMeters)) m", tint: WDColor.amber)
                        StatChip(icon: "checkmark.seal", label: "质量", value: "(analyzed.qualityScore)", tint: analyzed.qualityScore >= 70 ? WDColor.bamboo : WDColor.amber)
                    }
                } else {
                    Text("计划轨迹和历史活动分开保存；导入后会重新派生距离、爬升和时间质量。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                }
                GhostButton(title: hasRoute ? "重新导入 GPX" : "选择 GPX 文件", color: WDColor.ricePaper.opacity(0.85)) {
                    showImporter = true
                }
                if let error = session.planning.importError {
                    Text(error).font(WDFont.caption()).foregroundStyle(WDColor.cinnabar)
                }
            }
        }
    }

    private var subjectiveCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("只问今天有用的三件事").font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
                if session.planning.subjective["sleepHours"] == nil {
                    Text("昨晚睡了多久？").font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                    FlowChips(options: ["4 小时", "5.5 小时", "7 小时", "8 小时"]) { option in
                        let value = Double(option.split(separator: " ").first ?? "0") ?? 0
                        session.planning.answerSleep(value)
                    }
                }
                if session.planning.subjective["sleepHours"] != nil && session.planning.subjective["fatigue"] == nil {
                    Text("现在主观疲劳几分？").font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                    FlowChips(options: ["0", "3", "5", "7", "9"]) { session.planning.answerFatigue(Double($0) ?? 0) }
                }
                if session.planning.subjective["fatigue"] != nil && session.planning.subjective["pain"] == nil {
                    Text("现在有疼痛吗？").font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                    FlowChips(options: ["0", "2", "4", "6", "8"]) { session.planning.answerPain(Double($0) ?? 0) }
                }
                if subjectiveComplete {
                    Text("身体问询已完成，下面确认出发时间和真实补给。").font(WDFont.caption()).foregroundStyle(WDColor.bamboo)
                }
            }
        }
    }

    private var planQuestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(answered.indices, id: \.self) { i in answeredRow(answered[i]) }
            if let q = current {
                InkCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(q.rawValue).font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
                        FlowChips(options: q.options) { option in
                            Haptics.tap()
                            answered.append((q.rawValue, option))
                            session.answer(q, with: option)
                        }
                    }
                }
                .opacity(showCurrent ? 1 : 0)
            }
        }
    }

    private func answeredRow(_ item: (q: String, a: String)) -> some View {
        HStack {
            Text(item.q).font(WDFont.caption()).foregroundStyle(WDColor.mist)
            Spacer()
            Text(item.a).font(WDFont.body(13).weight(.medium)).foregroundStyle(WDColor.ink)
                .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(WDColor.ricePaper))
        }
    }

    private var healthStatus: String {
        switch session.planning.healthKit.authorizationState {
        case .granted: return "已授权"
        case .requesting: return "请求中"
        case .denied: return "未提供"
        case .unavailable: return "设备不可用"
        case .notDetermined: return "准备请求"
        }
    }

    private var healthTint: Color { healthStatus == "已授权" ? WDColor.bamboo : WDColor.amber }

    private var healthDetail: String {
        if let snapshot = session.planning.healthSnapshot, snapshot.readings.isEmpty { return "未读取到可用样本；继续用问卷补齐，不影响离线路线分析。" }
        return "只读取徒步准备相关指标；数值带采样时间，不把缺失数据猜成正常。"
    }

    private func healthValue(_ metric: HealthMetric, suffix: String) -> String {
        guard let value = session.planning.healthSnapshot?.reading(metric)?.value else { return "—" }
        return "\(String(format: "%.1f", value))\(suffix)"
    }
}

struct FlowChips: View {
    let options: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options, id: \.self) { opt in
                    Button { onTap(opt) } label: {
                        Text(opt).font(WDFont.body(14).weight(.medium)).foregroundStyle(WDColor.ricePaper)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Capsule().stroke(WDColor.mist.opacity(0.5), lineWidth: 1)
                                .background(Capsule().fill(WDColor.mossSurface)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
