import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Stage 1：行前采集（只保留 GPX + 过往经历）

struct PlanningChatView: View {
    @EnvironmentObject var session: TripSession
    @State private var showImporter = false

    private var exp: HikerExperience { session.planning.experience }
    private var experienceComplete: Bool { session.planning.experienceComplete }
    private var hasRoute: Bool { session.planning.analyzedGPX != nil }
    private var canBuild: Bool { experienceComplete && hasRoute }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    chatStream
                    if !experienceComplete {
                        experienceCard
                    } else {
                        experienceSummary
                    }
                    if session.planning.canImportGPX { routeCard }
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
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            session.planning.importGPX(from: url)
        }
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
                        .foregroundStyle(item.role == .user ? WDColor.onDark : WDColor.ricePaper)
                        .padding(.horizontal, item.role == .user ? 14 : 0)
                        .padding(.vertical, item.role == .user ? 9 : 0)
                        .background { if item.role == .user { Capsule().fill(WDColor.ink) } }
                        .frame(maxWidth: .infinity, alignment: item.role == .user ? .trailing : .leading)
                }
            }
        }
    }

    // MARK: 过往经历（唯一的人身输入）

    private var experienceCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("你走过最难的一次", systemImage: "figure.hiking")
                        .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                    Spacer()
                    Text("必填").font(WDFont.caption()).foregroundStyle(WDColor.amber)
                }
                Text("用你的经验上限判断这条路线对你的真实难度,并预估耗时。")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)

                if exp.hardestDistanceKm == 0 {
                    question("那次的距离是多少？", ["10 km", "15 km", "20 km", "25 km", "30 km"]) {
                        session.planning.answerHardestDistance(number($0))
                    }
                } else if exp.hardestAscentM == 0 {
                    question("累计拔高多少？", ["600 m", "1000 m", "1400 m", "1800 m", "2200 m"]) {
                        session.planning.answerHardestAscent(number($0))
                    }
                } else if exp.highestAltitudeM == 0 {
                    question("走过的最高海拔？", ["2000 m", "3000 m", "4000 m", "5000 m"]) {
                        session.planning.answerHighestAltitude(number($0))
                    }
                } else if exp.longestDurationH == 0 {
                    question("那次总共走了多久？", ["4 h", "6 h", "8 h", "10 h", "12 h"]) {
                        session.planning.answerLongestDuration(number($0))
                    }
                }
            }
        }
    }

    private var experienceSummary: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("你的经验上限", systemImage: "chart.line.uptrend.xyaxis")
                    .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                HStack(spacing: 8) {
                    StatChip(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "最难距离", value: String(format: "%.0f km", exp.hardestDistanceKm), tint: WDColor.bamboo)
                    StatChip(icon: "mountain.2", label: "最大拔高", value: "\(Int(exp.hardestAscentM)) m", tint: WDColor.amber)
                }
                HStack(spacing: 8) {
                    StatChip(icon: "arrow.up.to.line", label: "最高海拔", value: "\(Int(exp.highestAltitudeM)) m", tint: WDColor.bamboo)
                    StatChip(icon: "clock", label: "最长耗时", value: String(format: "%.0f h", exp.longestDurationH), tint: WDColor.amber)
                }
            }
        }
    }

    private func question(_ title: String, _ options: [String], _ onTap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
            FlowChips(options: options) { Haptics.tap(); onTap($0) }
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
                        StatChip(icon: "checkmark.seal", label: "质量", value: "\(analyzed.qualityScore)/100", tint: analyzed.qualityScore >= 70 ? WDColor.bamboo : WDColor.amber)
                    }
                } else {
                    Text("导入你下载的 GPX 轨迹(通常来自别人记录的路线)。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                }
                GhostButton(title: hasRoute ? "重新导入 GPX" : "选择 GPX 文件") {
                    showImporter = true
                }
                .accessibilityIdentifier("gpx-import-button")
                if let error = session.planning.importError {
                    Text(error).font(WDFont.caption()).foregroundStyle(WDColor.cinnabar)
                }
            }
        }
    }

    private func number(_ option: String) -> Double {
        Double(option.split(separator: " ").first ?? "0") ?? 0
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
                            .background(Capsule().stroke(WDColor.line, lineWidth: 1)
                                .background(Capsule().fill(WDColor.mossSurface)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
