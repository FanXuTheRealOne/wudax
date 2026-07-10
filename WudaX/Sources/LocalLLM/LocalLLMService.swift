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
                let input = try await context.processor.prepare(input: UserInput(chat: chat))
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
