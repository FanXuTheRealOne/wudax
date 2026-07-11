import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - 本地小模型服务
// 端侧运行 Qwen3-0.6B-4bit（约 335MB）。
// 模型权重已随 App 打包（BundledModel/LLMModel → .app/LLMModel），
// 用 ModelConfiguration(directory:) 从包内本地加载，完全不联网、装好即离线可用。
// 依赖 Apple MLX（Metal GPU）——必须在真机运行，模拟器不支持。

@MainActor
final class LocalLLMService: ObservableObject {

    /// 模型加载状态
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    struct Msg: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        var text: String
        enum Role { case user, assistant }
    }

    @Published var loadState: LoadState = .idle
    @Published var messages: [Msg] = []
    @Published var isGenerating = false

    private var container: ModelContainer?

    /// 打包进 App 的模型目录名（folder reference：.app/LLMModel）
    private let bundledFolder = "LLMModel"
    private let maxTokens = 512
    private let systemPrompt = """
    你是 WUDAX 的徒步助手。WUDAX 是一款为徒步者做疲劳与风险管理的产品，品牌内核取自庄子「无待」——平时安静，关键时刻主动。
    请用简体中文、简洁口语化地回答关于徒步计划、补给、体力、装备与撤退决策的问题。不要给医疗结论。
    """

    // MARK: 加载模型（从 App 包内本地目录，不联网）

    func loadIfNeeded() async {
        guard container == nil else { return }
        if case .loading = loadState { return }
        // MLX 初始化 Metal 设备在模拟器上会直接 abort(不是抛错),必须提前拦截;
        // 拦截后所有调用方(首页问答/行中 agent)自动降级为规则引擎文案。
        #if targetEnvironment(simulator)
        loadState = .failed("模拟器不支持端侧模型,需真机 Metal GPU")
        return
        #else
        loadState = .loading
        do {
            guard let base = Bundle.main.resourceURL else {
                throw NSError(domain: "WUDAX", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "找不到 App 资源目录"])
            }
            let modelURL = base.appendingPathComponent(bundledFolder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: modelURL.path) else {
                throw NSError(domain: "WUDAX", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "App 内未找到模型（\(bundledFolder)），请确认已打包"])
            }
            let config = ModelConfiguration(directory: modelURL)
            container = try await LLMModelFactory.shared.loadContainer(configuration: config)
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
        #endif
    }

    // MARK: 纯生成接口(行中 Agent 等调用方共用同一模型容器)

    /// 给定 system + 对话历史直接生成一段回复;不读写 `messages`(那是首页问答窗口的状态)。
    func respond(system: String,
                 history: [(role: Msg.Role, text: String)],
                 maxTokens: Int = 512) async throws -> String {
        await loadIfNeeded()
        guard case .ready = loadState, let container else {
            throw NSError(domain: "WUDAX", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "本地模型未就绪(需要真机 Metal GPU)"])
        }
        var chat: [Chat.Message] = [.system(system)]
        for item in history {
            switch item.role {
            case .user: chat.append(.user(item.text))
            case .assistant: chat.append(.assistant(item.text))
            }
        }
        let cap = maxTokens
        let result = try await container.perform { [chat] context -> GenerateResult in
            let input = try await context.processor.prepare(input: UserInput(chat: chat))
            return try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.6),
                context: context
            ) { tokens in
                tokens.count >= cap ? .stop : .more
            }
        }
        return Self.stripThinking(result.output)
    }

    /// 剥离 Qwen3 思考模式的 <think>…</think> 段(含未闭合的残段)。
    nonisolated static func stripThinking(_ text: String) -> String {
        var output = text
        while let start = output.range(of: "<think>"),
              let end = output.range(of: "</think>", range: start.upperBound..<output.endIndex) {
            output.removeSubrange(start.lowerBound..<end.upperBound)
        }
        if let orphan = output.range(of: "<think>") {
            output.removeSubrange(orphan.lowerBound..<output.endIndex)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 发送一条消息并流式生成

    func send(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        await loadIfNeeded()
        guard case .ready = loadState, let container else { return }

        messages.append(Msg(role: .user, text: trimmed))
        messages.append(Msg(role: .assistant, text: ""))
        let replyIndex = messages.count - 1
        isGenerating = true

        // 组装对话历史（丢掉最后那条空的 assistant 占位）
        var chat: [Chat.Message] = [.system(systemPrompt)]
        for m in messages.dropLast() {
            switch m.role {
            case .user: chat.append(.user(m.text))
            case .assistant where !m.text.isEmpty: chat.append(.assistant(m.text))
            default: break
            }
        }

        let cap = maxTokens
        do {
            let result = try await container.perform { [chat] context -> GenerateResult in
                let input = try await context.processor.prepare(input: UserInput(chat: chat, tools: AgentToolOrchestrator.toolSpecifications))
                return try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0.6),
                    context: context
                ) { tokens in
                    let text = context.tokenizer.decode(tokens: tokens)
                    Task { @MainActor in
                        if self.messages.indices.contains(replyIndex) {
                            self.messages[replyIndex].text = text
                        }
                    }
                    return tokens.count >= cap ? .stop : .more
                }
            }
            if messages.indices.contains(replyIndex) {
                messages[replyIndex].text = result.output
            }
        } catch {
            if messages.indices.contains(replyIndex) {
                messages[replyIndex].text = "⚠️ 生成失败：\(error.localizedDescription)"
            }
        }
        isGenerating = false
    }
}
