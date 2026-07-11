import Foundation
import Combine
import AVFoundation
import Speech

// MARK: - 全局 WUDAX Agent
// App 级唯一实例(对应架构图最外层的 agent 圈);每次徒步 session 在其内部
// 开一个独立的 AgentSessionContext(图里的 session 小圈):对话历史、播报记忆、
// 冷却状态都隔离在各自 context 中,互不串扰。LLM 容器全局只加载一次。
//
// 职责分工不变:规则引擎是安全层(判级/动作),LLM 只是表达层——
// 主动播报与问答都基于 AgentDataBus 的真实数据快照,LLM 不可用时降级为规则文案。

/// session 内的一条 agent 消息。
struct AgentMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant, proactive }

    let id = UUID()
    var role: Role
    var text: String
    var date: Date
    /// 主动播报对应的信号标题(UI 上作角标)。
    var signalHeadline: String?
    /// true = LLM 不可用,内容为规则引擎文案。
    var isFallback = false
}

/// Agent 语音功能的用户偏好。默认 text-only,避免一进页面就抢麦克风或突然外放。
struct AgentVoicePreferences: Equatable {
    var voiceInputEnabled = false
    var spokenRepliesEnabled = false
    var proactiveSpeechEnabled = false

    func shouldSpeak(role: AgentMessage.Role) -> Bool {
        switch role {
        case .assistant:
            return spokenRepliesEnabled
        case .proactive:
            return spokenRepliesEnabled && proactiveSpeechEnabled
        case .user:
            return false
        }
    }
}

enum AgentVoiceRuntimeStatus: Equatable {
    case idle
    case requestingPermission
    case listening
    case transcribing(String)
    case speaking
    case permissionDenied
    case recognitionUnavailable
    case onDeviceRecognitionUnavailable
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "语音待命"
        case .requestingPermission:
            return "正在请求语音权限"
        case .listening:
            return "正在听你说话"
        case .transcribing(let text):
            return text.isEmpty ? "正在识别语音" : "识别中:\(text)"
        case .speaking:
            return "正在播报"
        case .permissionDenied:
            return "麦克风或语音识别权限未开启"
        case .recognitionUnavailable:
            return "语音识别暂不可用"
        case .onDeviceRecognitionUnavailable:
            return "当前设备不支持离线语音识别"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class AgentVoiceIOService: NSObject, ObservableObject {
    @Published private(set) var status: AgentVoiceRuntimeStatus = .idle
    @Published private(set) var partialTranscript = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isListening: Bool { audioEngine.isRunning }

    func requestPermissions() async -> Bool {
        status = .requestingPermission
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            status = .permissionDenied
            return false
        }

        let speechGranted = await requestSpeechPermission()
        guard speechGranted else {
            status = .permissionDenied
            return false
        }

        status = .idle
        return true
    }

    func startListening(onFinalTranscript: @escaping @MainActor (String) -> Void) async {
        guard await requestPermissions() else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            status = .recognitionUnavailable
            return
        }

        stopListening(submitPartial: false)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            status = .onDeviceRecognitionUnavailable
            return
        }

        recognitionRequest = request
        partialTranscript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            status = .listening

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let text = result?.bestTranscription.formattedString {
                        self.partialTranscript = text
                        self.status = .transcribing(text)
                    }

                    if result?.isFinal == true {
                        let final = self.partialTranscript
                        self.stopListening(submitPartial: false)
                        onFinalTranscript(final)
                    } else if error != nil {
                        self.stopListening(submitPartial: false)
                        self.status = .failed("语音识别中断，请再试一次")
                    }
                }
            }
        } catch {
            stopListening(submitPartial: false)
            status = .failed("麦克风启动失败")
        }
    }

    func stopListening(submitPartial: Bool = true, onFinalTranscript: (@MainActor (String) -> Void)? = nil) {
        let final = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        partialTranscript = ""
        status = .idle

        if submitPartial, !final.isEmpty {
            onFinalTranscript?(final)
        }
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 0.98
        status = .speaking
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        status = .idle
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

extension AgentVoiceIOService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.status = .idle
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.status = .idle
        }
    }
}

/// 一次徒步 session 的独立 agent 上下文。
@MainActor
final class AgentSessionContext: ObservableObject, Identifiable {
    let id = UUID()
    let routeName: String
    let startedAt: Date
    var endedAt: Date?

    @Published var messages: [AgentMessage] = []
    @Published var unreadCount = 0
    var signalMemory = AgentSignalMemory()

    init(routeName: String, startedAt: Date = Date()) {
        self.routeName = routeName
        self.startedAt = startedAt
    }
}

@MainActor
final class WudaXAgent: ObservableObject {

    /// 当前行程的 context;非行中为 nil。
    @Published private(set) var activeContext: AgentSessionContext?
    /// 已结束 session 的归档(内存;持久化列为后续工作)。
    @Published private(set) var archivedContexts: [AgentSessionContext] = []
    /// 最近一条主动播报,行中页 banner 展示用。
    @Published var latestBanner: AgentMessage?
    /// 问答生成中(播报生成不置此标志)。
    @Published private(set) var isResponding = false
    @Published var voicePreferences = AgentVoicePreferences()

    let llm: LocalLLMService
    let voice: AgentVoiceIOService

    private weak var session: TripSession?
    private var cancellables = Set<AnyCancellable>()
    private var isAnnouncing = false

    private static let persona = """
    你是 WUDAX 行中智能体,陪伴用户完成当前徒步。给你的「快照」是本次行程的全部真实数据。\
    「安全结论」由确定性规则引擎给出,你必须以它为准,不得给出比它更激进或更宽松的安全建议,不给医疗诊断。\
    用简体中文,口语、具体、简短;引用的数字必须来自快照,不要编造。
    """

    init(llm: LocalLLMService? = nil, voice: AgentVoiceIOService? = nil) {
        self.llm = llm ?? LocalLLMService()
        self.voice = voice ?? AgentVoiceIOService()
    }

    // MARK: 挂接 TripSession(TripSession 本身零改动)

    func attach(_ session: TripSession) {
        guard self.session !== session else { return }
        self.session = session
        cancellables.removeAll()

        session.$phase
            .removeDuplicates()
            .sink { [weak self] phase in self?.handlePhase(phase) }
            .store(in: &cancellables)

        // 状态变化驱动信号检测;节流避免每个 GPS 点都跑一遍。
        session.objectWillChange
            .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.evaluateSignals() }
            }
            .store(in: &cancellables)

        // 定时兜底:界面无变化时(如后台定位停发)也保持检测。
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.evaluateSignals() }
            .store(in: &cancellables)
    }

    func markRead() {
        activeContext?.unreadCount = 0
        latestBanner = nil
    }

    // MARK: session context 生命周期

    private func handlePhase(_ phase: TripSession.Phase) {
        switch phase {
        case .inTrip:
            startContextIfNeeded()
        default:
            endContextIfNeeded()
        }
    }

    private func startContextIfNeeded() {
        guard activeContext == nil, let session else { return }
        activeContext = AgentSessionContext(routeName: session.plan.route.name)
        latestBanner = nil
        // 预热模型(真机);失败静默,后续全部走规则文案。
        Task { await llm.loadIfNeeded() }
    }

    private func endContextIfNeeded() {
        guard let context = activeContext else { return }
        context.endedAt = Date()
        archivedContexts.insert(context, at: 0)
        activeContext = nil
        latestBanner = nil
    }

    // MARK: 主动播报

    private func evaluateSignals() {
        guard let session, session.phase == .inTrip,
              let context = activeContext, !isAnnouncing else { return }

        if let hr = session.latestHealthSnapshot?.reading(.heartRate)?.value {
            AgentSignalDetector.recordHeartRate(hr, memory: &context.signalMemory)
        }

        let input = signalInput(from: session)
        guard let signal = AgentSignalDetector.detect(input: input,
                                                      memory: &context.signalMemory) else { return }
        isAnnouncing = true
        Task { [weak self] in
            await self?.announce(signal, in: context)
            self?.isAnnouncing = false
        }
    }

    private func signalInput(from session: TripSession) -> AgentSignalInput {
        var input = AgentSignalInput()
        input.isRecording = session.trackingState == .recording
        input.verdict = session.lastDecision?.verdict
            ?? AgentEngine.evaluate(status: session.status, plan: session.plan).verdict
        if let match = session.routeMatch {
            input.isOffRoute = match.isOffRoute
            input.distanceToRouteMeters = match.distanceToRouteMeters
        }
        input.heartRateBPM = session.latestHealthSnapshot?.reading(.heartRate)?.value
        input.planDeltaMin = session.status.planDeltaMin
        input.hoursToSunset = session.status.hoursToSunset
        if let prepared = session.preparedRoute, prepared.totalDistanceMeters > 0 {
            input.progressFraction = (session.routeMatch?.routeProgressMeters ?? 0) / prepared.totalDistanceMeters
        }
        if let risk = AgentDataBus.lookahead(session: session)?.upcomingRiskPoints.first {
            input.upcomingRisk = (risk.title, risk.distanceMeters)
        }
        return input
    }

    private func announce(_ signal: AgentSignal, in context: AgentSessionContext) async {
        guard let session else { return }
        var message = AgentMessage(role: .proactive,
                                   text: fallbackText(for: signal, session: session),
                                   date: Date(),
                                   signalHeadline: signal.headline,
                                   isFallback: true)

        if llm.loadState == .ready, !llm.isGenerating {
            let prompt = """
            \(signalDescription(signal))
            \(AgentDataBus.compactSnapshot(session: session))
            请把上面的变化用一两句自然的话主动告诉用户(第一人称对话口吻,不要重复所有数字,只说重点)。 /no_think
            """
            if let generated = try? await llm.respond(system: Self.persona,
                                                      history: [(role: .user, text: prompt)],
                                                      maxTokens: 120),
               !generated.isEmpty {
                message.text = generated
                message.isFallback = false
            }
        }

        context.messages.append(message)
        context.unreadCount += 1
        latestBanner = message
        speakIfNeeded(message)
        Haptics.tap()
    }

    private func signalDescription(_ signal: AgentSignal) -> String {
        switch signal {
        case .sessionStart:
            return "刚到达路线起点,行程开始。请做一段简短开场:提醒总里程/爬升、最先遇到的风险点和日落窗口。"
        case .verdictChanged(let verdict):
            return "规则引擎判级刚变为「\(verdict.rawValue)」。"
        case .offRouteChanged(let isOff, let distance):
            return isOff ? "刚检测到可能偏离路线,距路线约 \(Int(distance)) m。" : "已回到计划路线上。"
        case .heartRateShift(let bpm, let baseline):
            let base = baseline.map { ",本次行程基线约 \(Int($0)) bpm" } ?? ""
            return "心率变为 \(Int(bpm)) bpm\(base)。"
        case .paceBandChanged(let delta):
            return "进度落后计划 \(-delta) 分钟。"
        case .sunsetWindow(let hours):
            return String(format: "距日落只剩 %.1f 小时。", hours)
        case .upcomingRiskPoint(let title, let distance):
            return "前方 \(Int(distance)) m 即将到达「\(title)」。"
        case .progressMilestone(let percent):
            return "已完成全程 \(percent)%。"
        }
    }

    /// LLM 不可用时的规则文案(信号 + 规则引擎现成中文)。
    private func fallbackText(for signal: AgentSignal, session: TripSession) -> String {
        switch signal {
        case .sessionStart:
            let route = session.plan.route
            var text = String(format: "行程开始。全程 %.1f km、爬升 %d m,预计 %.1f 小时。",
                              route.distanceKm, Int(route.ascentM), route.estimatedHours)
            if let risk = AgentDataBus.lookahead(session: session)?.upcomingRiskPoints.first {
                text += "最先注意:\(risk.title)。"
            }
            return text
        case .verdictChanged:
            let decision = session.lastDecision ?? AgentEngine.evaluate(status: session.status, plan: session.plan)
            return decision.watchHint
        case .offRouteChanged(let isOff, let distance):
            return isOff ? "连续定位显示可能偏离路线,距路线约 \(Int(distance)) m,请对照地图确认。" : "已回到计划路线,继续保持。"
        case .heartRateShift(let bpm, _):
            return "最近心率 \(Int(bpm)) bpm,注意配速与补水,必要时休息。"
        case .paceBandChanged(let delta):
            return "目前落后计划 \(-delta) 分钟,留意日落前的时间余量。"
        case .sunsetWindow(let hours):
            return String(format: "距日落 %.1f 小时,请评估剩余路程与撤退窗口。", hours)
        case .upcomingRiskPoint(let title, let distance):
            return "前方 \(Int(distance)) m:\(title),提前调整节奏。"
        case .progressMilestone(let percent):
            return "已完成 \(percent)%,状态如常,继续保持。"
        }
    }

    // MARK: 对话

    /// 用户在 AI 窗口发问:全量快照 + 本 context 历史 → LLM。
    func ask(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding,
              let session, let context = activeContext else { return }

        context.messages.append(AgentMessage(role: .user, text: trimmed, date: Date()))
        isResponding = true
        defer { isResponding = false }

        // 0.6B 小模型对 system prompt 中大段资料的检索能力很弱:把全量快照
        // 直接嵌进当前这条 user 消息、紧贴问题本身,它才会真的使用这些数据;
        // system 只留简短人设,历史只带纯对话文本。
        let snapshot = AgentDataBus.fullSnapshot(session: session)
        let question = """
        【当前行程快照(唯一事实来源)】
        \(snapshot)

        用户问题:\(trimmed)
        只根据上面的快照回答,引用其中的数字;快照里没有的信息就直说没有。用一到三句口语中文。 /no_think
        """

        // 只带当前 session context 的对话历史(独立 context 的关键);
        // 去掉刚追加的这条 user 消息,它以带快照的形式重新加入。
        var history: [(role: LocalLLMService.Msg.Role, text: String)] =
            context.messages.dropLast().suffix(8).map {
                (role: $0.role == .user ? .user : .assistant, text: $0.text)
            }
        history.append((role: .user, text: question))

        do {
            let reply = try await llm.respond(system: Self.persona, history: history, maxTokens: 320)
            guard !reply.isEmpty else { throw NSError(domain: "WUDAX", code: -4) }
            let message = AgentMessage(role: .assistant, text: reply, date: Date())
            context.messages.append(message)
            speakIfNeeded(message)
        } catch {
            // 模拟器/加载失败/空输出:退回数据摘要,窗口仍然有用。
            let fallback = "本机模型暂不可用,给你当前数据摘要:\n" + AgentDataBus.compactSnapshot(session: session)
            let message = AgentMessage(role: .assistant, text: fallback, date: Date(), isFallback: true)
            context.messages.append(message)
            speakIfNeeded(message)
        }
    }

    // MARK: 语音输入/输出

    func toggleVoiceInput() {
        voicePreferences.voiceInputEnabled.toggle()
        if !voicePreferences.voiceInputEnabled {
            voice.stopListening()
        }
    }

    func toggleSpokenReplies() {
        voicePreferences.spokenRepliesEnabled.toggle()
        if !voicePreferences.spokenRepliesEnabled {
            voice.stopSpeaking()
        }
    }

    func toggleProactiveSpeech() {
        voicePreferences.proactiveSpeechEnabled.toggle()
        if voicePreferences.proactiveSpeechEnabled {
            voicePreferences.spokenRepliesEnabled = true
        }
    }

    func startVoiceQuestion() {
        guard voicePreferences.voiceInputEnabled else { return }
        Task {
            await voice.startListening { [weak self] transcript in
                Task { await self?.handleRecognizedVoiceText(transcript) }
            }
        }
    }

    func stopVoiceQuestion() {
        voice.stopListening { [weak self] transcript in
            Task { await self?.handleRecognizedVoiceText(transcript) }
        }
    }

    func handleRecognizedVoiceText(_ text: String) async {
        await ask(text)
    }

    private func speakIfNeeded(_ message: AgentMessage) {
        guard voicePreferences.shouldSpeak(role: message.role) else { return }
        voice.speak(message.text)
    }
}
