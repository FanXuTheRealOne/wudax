import SwiftUI

// MARK: - 行中 AI 窗口
// session 开始后的 agent 对话界面:主动播报与问答混排在同一条消息流里,
// 数据全部来自当前 AgentSessionContext(每个 session 独立,互不串扰)。

struct SessionAgentView: View {
    @EnvironmentObject var agent: WudaXAgent
    @EnvironmentObject var session: TripSession
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var context: AgentSessionContext? { agent.activeContext }

    private static let quickQuestions = [
        "前面路怎么样?",
        "我现在状态怎么样?",
        "还要走多久?",
        "水够撑到终点吗?"
    ]

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                llmStatusRow
                messageList
                quickChips
                inputBar
            }
        }
        .onAppear { agent.markRead() }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(WDColor.bamboo).frame(width: 9, height: 9)
                .overlay(Circle().stroke(WDColor.bamboo.opacity(0.35), lineWidth: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text("WUDAX Agent").font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
                Text(context?.routeName ?? session.plan.route.name)
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist).lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(WDColor.ricePaper)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder
    private var llmStatusRow: some View {
        switch agent.llm.loadState {
        case .ready:
            EmptyView()
        case .loading:
            statusLine("端侧模型加载中,先用规则引擎回复…", icon: "hourglass", tint: WDColor.mist)
        case .failed:
            statusLine("本机模型不可用(需真机),当前为规则引擎文案", icon: "cpu", tint: WDColor.amber)
        case .idle:
            statusLine("端侧离线小模型 · 数据不出手机", icon: "lock.shield", tint: WDColor.mist)
        }
    }

    private func statusLine(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(WDFont.caption(11))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(WDColor.mossSurface.opacity(0.6))
    }

    // MARK: 消息流

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if (context?.messages.isEmpty ?? true) {
                        emptyHint
                    }
                    ForEach(context?.messages ?? []) { message in
                        messageRow(message).id(message.id)
                    }
                    if agent.isResponding {
                        HStack(spacing: 8) {
                            ProgressView().tint(WDColor.bamboo).scaleEffect(0.8)
                            Text("正在结合行程数据回答…")
                                .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                        }
                        .id("generating")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .onChange(of: context?.messages.count ?? 0) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    if let last = context?.messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("我在陪你走这条路线", systemImage: "figure.hiking")
                    .font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper)
                Text("心率、配速、偏航、前方路况有值得说的变化时,我会主动开口;你也可以随时问我行程里的任何数据。")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AgentMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(WDFont.body(14)).foregroundStyle(WDColor.onDark)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16).fill(WDColor.ink))
            }
        case .proactive:
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(WDColor.amber).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .font(.system(size: 10)).foregroundStyle(WDColor.amber)
                        Text(message.signalHeadline ?? "主动提醒")
                            .font(WDFont.caption(10).weight(.semibold)).foregroundStyle(WDColor.amber)
                        Text(timeText(message.date))
                            .font(WDFont.caption(10)).foregroundStyle(WDColor.mist.opacity(0.7))
                        if message.isFallback { fallbackTag }
                    }
                    Text(message.text)
                        .font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 24)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(WDColor.deepMoss)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(WDColor.amber.opacity(0.25), lineWidth: 1)))
        case .assistant:
            HStack(alignment: .top, spacing: 9) {
                Circle().fill(WDColor.bamboo).frame(width: 7, height: 7).padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    if message.isFallback { fallbackTag }
                    Text(message.text)
                        .font(WDFont.body(14)).foregroundStyle(WDColor.ricePaper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 24)
            }
        }
    }

    private var fallbackTag: some View {
        Text("规则文案")
            .font(WDFont.caption(9)).foregroundStyle(WDColor.mist)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(WDColor.mossSurface))
    }

    // MARK: 快捷问题 + 输入

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickQuestions, id: \.self) { question in
                    Button {
                        Haptics.tap()
                        Task { await agent.ask(question) }
                    } label: {
                        Text(question)
                            .font(WDFont.caption(12)).foregroundStyle(WDColor.ricePaper)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(WDColor.mossSurface))
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.isResponding)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("问问行程里的任何数据…", text: $input, axis: .vertical)
                .font(WDFont.body(14))
                .foregroundStyle(WDColor.ricePaper)
                .lineLimit(1...3)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(WDColor.deepMoss)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(WDColor.line, lineWidth: 1)))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? WDColor.ink : WDColor.mist.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !agent.isResponding
    }

    private func send() {
        guard canSend else { return }
        let text = input
        input = ""
        Haptics.tap()
        Task { await agent.ask(text) }
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
}
