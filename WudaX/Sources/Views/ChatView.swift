import SwiftUI

// MARK: - 本地 AI 聊天窗口
// 端侧 Qwen3-0.6B 推理；首次进入触发模型下载（约 335MB），之后离线可用。

struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    // 全局共享的模型服务(与行中 WudaXAgent 同一个容器,权重只加载一次)。
    @EnvironmentObject var llm: LocalLLMService
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            ContourBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                statusBanner
                messageList
                inputBar
            }
        }
        .task { await llm.loadIfNeeded() }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("WUDAX 助手").font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
                Text("Qwen3 0.6B · 端侧离线").font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
            }
            Spacer()
            Color.clear.frame(width: 17, height: 17)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    // MARK: 模型状态条

    @ViewBuilder private var statusBanner: some View {
        switch llm.loadState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().tint(WDColor.amber).scaleEffect(0.8)
                Text("正在载入本地模型…").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                Spacer()
            }
            .padding(.horizontal, 22).padding(.bottom, 10)
        case .failed(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(WDColor.cinnabar)
                Text("加载失败：\(msg)").font(WDFont.caption()).foregroundStyle(WDColor.cinnabar)
                    .lineLimit(2)
                Spacer()
                Button("重试") { Task { await llm.loadIfNeeded() } }
                    .font(WDFont.caption().weight(.semibold)).foregroundStyle(WDColor.amber)
            }
            .padding(.horizontal, 22).padding(.bottom, 10)
        default:
            EmptyView()
        }
    }

    // MARK: 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if llm.messages.isEmpty { emptyHint }
                    ForEach(llm.messages) { m in
                        bubble(m).id(m.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .onChange(of: llm.messages.last?.text) { _, _ in
                if let last = llm.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "mountain.2")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(WDColor.mist.opacity(0.6))
            Text("问问关于徒步计划、补给或撤退的事")
                .font(WDFont.body(14)).foregroundStyle(WDColor.mist)
            Text("全部在你手机本地运行，不联网")
                .font(WDFont.caption()).foregroundStyle(WDColor.mist.opacity(0.6))
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    @ViewBuilder private func bubble(_ m: LocalLLMService.Msg) -> some View {
        let isUser = m.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(m.text.isEmpty ? "…" : m.text)
                .font(WDFont.body(15))
                .foregroundStyle(isUser ? WDColor.onDark : WDColor.ricePaper)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isUser ? WDColor.ink : WDColor.deepMoss)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isUser ? .clear : WDColor.mossSurface, lineWidth: 1)
                )
            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: 输入栏

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("和 WUDAX 聊聊…", text: $draft, axis: .vertical)
                .font(WDFont.body(15))
                .foregroundStyle(WDColor.ricePaper)
                .tint(WDColor.amber)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20).fill(WDColor.deepMoss))

            Button {
                let text = draft
                draft = ""
                inputFocused = false
                Task { await llm.send(text) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WDColor.inkPine)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend ? WDColor.amber : WDColor.mossSurface))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(WDColor.inkPine)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !llm.isGenerating
            && llm.loadState == .ready
    }
}
