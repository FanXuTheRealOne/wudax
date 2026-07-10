import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - 本地小模型服务
// 端侧运行 mlx-community/Qwen3-0.6B-4bit（约 335MB）
// 首次启动从 HuggingFace 下载参数，缓存进 App 沙盒，之后完全离线。
// 依赖 Apple MLX（Metal GPU）——必须在真机运行，模拟器不支持。

@MainActor
final class LocalLLMService: ObservableObject {

    /// 模型加载状态
    enum LoadState: Equatable {
        case idle
        case downloading(Double)   // 0...1
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

    /// 目标模型：Qwen3 0.6B 4-bit 量化
    private let modelId = "mlx-community/Qwen3-0.6B-4bit"
    private let maxTokens = 512
    private let systemPrompt = """
    你是 WUDAX 的徒步助手。WUDAX 是一款为徒步者做疲劳与风险管理的产品，品牌内核取自庄子「无待」——平时安静，关键时刻主动。
    请用简体中文、简洁口语化地回答关于徒步计划、补给、体力、装备与撤退决策的问题。不要给医疗结论。
    """

    // MARK: 加载模型（首次触发下载）

    func loadIfNeeded() async {
        guard container == nil else { return }
        if case .downloading = loadState { return }
        loadState = .downloading(0)
        do {
            let config = ModelConfiguration(id: modelId)
            let loaded = try await LLMModelFactory.shared.loadContainer(configuration: config) { [weak self] progress in
                Task { @MainActor in
                    self?.loadState = .downloading(progress.fractionCompleted)
                }
            }
            container = loaded
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
