import SwiftUI

// MARK: - 阶段五：行后复盘

struct ReviewView: View {
    @EnvironmentObject var session: TripSession
    @State private var currentIndex = 0
    @State private var showSummary = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                if showSummary {
                    summary
                } else {
                    questionFlow
                }
            }
            .padding(.horizontal, 22)
        }
        .background(alignment: .top) { duskHeader }
    }

    private var duskHeader: some View {
        Group {
            if let ui = UIImage(named: "ink_mountains_dusk") {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(height: 260).frame(maxWidth: .infinity).clipped()
                    .mask(LinearGradient(
                        stops: [.init(color: .black, location: 0),
                                .init(color: .black, location: 0.55),
                                .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom))
                    .opacity(0.9)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.tripEndedByRetreat ? "今天的下撤，是对的决定。" : "行程结束")
                .font(WDFont.title(28)).foregroundStyle(WDColor.ricePaper)
                .padding(.top, 120)
            Text("趁记忆还热，复盘今天真实的失控点。")
                .font(WDFont.body(14)).foregroundStyle(WDColor.mist)
        }
    }

    private var questionFlow: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 已回答
            ForEach(0..<currentIndex, id: \.self) { i in
                HStack {
                    Text(session.reviewEntries[i].question)
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                        .lineLimit(1)
                    Spacer()
                    Text(session.reviewEntries[i].answer ?? "")
                        .font(WDFont.body(13).weight(.medium)).foregroundStyle(WDColor.bambooText)
                }
            }

            if currentIndex < session.reviewEntries.count {
                let entry = session.reviewEntries[currentIndex]
                InkCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(currentIndex + 1) / \(session.reviewEntries.count)")
                            .font(WDFont.mono(12)).foregroundStyle(WDColor.mist)
                        Text(entry.question)
                            .font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 10) {
                            ForEach(entry.options, id: \.self) { opt in
                                Button {
                                    Haptics.tap()
                                    session.reviewEntries[currentIndex].answer = opt
                                    withAnimation(.spring(duration: 0.5)) {
                                        if currentIndex + 1 < session.reviewEntries.count {
                                            currentIndex += 1
                                        } else {
                                            showSummary = true
                                        }
                                    }
                                } label: {
                                    Text(opt)
                                        .font(WDFont.body(14))
                                        .foregroundStyle(WDColor.ricePaper)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(WDColor.mossSurface))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
                .id(currentIndex)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            InkCard(light: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("本次失控点", systemImage: "exclamationmark.circle")
                        .font(WDFont.heading(16)).foregroundStyle(WDColor.ink)
                    ForEach(controlLossPoints, id: \.self) { p in
                        Text("· \(p)").font(WDFont.body(14)).foregroundStyle(WDColor.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            InkCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("下次类似路线建议", systemImage: "arrow.turn.up.right")
                        .font(WDFont.heading(16)).foregroundStyle(WDColor.bamboo)
                    Text("· 水量按 3.0 L 起步，发云界强制补满")
                    Text("· 长下坡前主动使用登山杖，控制步频")
                    Text("· 14:30 未到下坡起点即降级")
                }
                .font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
            }
            InkCard {
                HStack(spacing: 14) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 22, weight: .light)).foregroundStyle(WDColor.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("疲劳档案已更新").font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper)
                        Text("下坡耐受微调 · 补给速率重估")
                            .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    }
                    Spacer()
                }
            }
            PillButton(title: "完成复盘") { session.finishReview() }
                .padding(.bottom, 30)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var controlLossPoints: [String] {
        var pts: [String] = []
        if let a = session.reviewEntries.first(where: { $0.question.contains("补给") })?.answer,
           a != "全程充足" { pts.append("补给：从「\(a)」开始不够") }
        if let a = session.reviewEntries.first(where: { $0.question.contains("膝痛") })?.answer,
           a != "没有膝痛" { pts.append("膝盖：疼痛起于\(a)") }
        if let a = session.reviewEntries.first(where: { $0.question.contains("只想走出去") })?.answer,
           a != "没有出现" { pts.append("心态：\(a)开始只想走出去") }
        if pts.isEmpty { pts.append("本次行程整体在控制范围内") }
        return pts
    }
}

extension WDColor {
    static let bambooText = bamboo
}
