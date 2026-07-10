import SwiftUI

// MARK: - 阶段一：行前追问（Agent 主动补齐缺失信息）

struct PlanningChatView: View {
    @EnvironmentObject var session: TripSession
    @State private var answered: [(q: String, a: String)] = []
    @State private var showCurrent = false

    private var current: PlanQuestion? { session.plan.missingQuestions.first }
    private var total: Int { PlanQuestion.allCases.count }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    routeSummary
                    ForEach(answered.indices, id: \.self) { i in
                        answeredRow(answered[i])
                    }
                    if let q = current {
                        questionCard(q)
                            .opacity(showCurrent ? 1 : 0)
                            .offset(y: showCurrent ? 0 : 16)
                    }
                }
                .padding(22)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7).delay(0.3)) { showCurrent = true }
        }
    }

    private var topBar: some View {
        HStack {
            Button { session.phase = .home } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Text("行前确认")
                .font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Text("\(total - session.plan.missingQuestions.count + (current == nil ? 0 : 1))/\(total)")
                .font(WDFont.mono(13)).foregroundStyle(WDColor.mist)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var routeSummary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(WDColor.mossSurface)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 15)).foregroundStyle(WDColor.ricePaper)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("路线已解析：\(session.plan.route.name)")
                    .font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
                Text("在生成预算卡之前，我需要确认几件事。")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
            }
        }
    }

    private func answeredRow(_ item: (q: String, a: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.q).font(WDFont.body(14)).foregroundStyle(WDColor.mist)
            Text(item.a)
                .font(WDFont.body(15).weight(.medium))
                .foregroundStyle(WDColor.ink)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(WDColor.ricePaper))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func questionCard(_ q: PlanQuestion) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(q.rawValue)
                    .font(WDFont.heading(19))
                    .foregroundStyle(WDColor.ricePaper)
                if q == .water {
                    Text("路线后半程补水点稀少，这个数字很重要。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.amber)
                }
                FlowChips(options: q.options) { opt in
                    Haptics.tap()
                    answered.append((q.rawValue, opt))
                    showCurrent = false
                    session.answer(q, with: opt)
                    withAnimation(.spring(duration: 0.6).delay(0.25)) { showCurrent = true }
                }
            }
        }
    }
}

// MARK: - 快捷回复选项

struct FlowChips: View {
    let options: [String]
    let onTap: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.self) { opt in
                Button { onTap(opt) } label: {
                    Text(opt)
                        .font(WDFont.body(14).weight(.medium))
                        .foregroundStyle(WDColor.ricePaper)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            Capsule().stroke(WDColor.mist.opacity(0.5), lineWidth: 1)
                                .background(Capsule().fill(WDColor.mossSurface))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
