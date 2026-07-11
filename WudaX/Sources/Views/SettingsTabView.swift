import SwiftUI
import UIKit

/// 「设置」Tab —— 外骨骼 3D 展示、健康授权入口、关于。
struct SettingsTabView: View {
    @EnvironmentObject var session: TripSession
    @EnvironmentObject var sessionAgent: WudaXAgent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRequestingHealth = false
    @State private var showHealthResult = false
    @State private var healthResultMessage = ""
    @State private var modelLoadState: Bool?
    @State private var modelAppeared = false

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            ContourBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    exoskeletonSection

                    voiceGroup

                    settingsGroup

                    aboutCard
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
        }
        .alert("Apple Health", isPresented: $showHealthResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(healthResultMessage)
        }
        .task {
            await session.refreshAppleHealthAccess()
        }
        .onAppear {
            if reduceMotion {
                modelAppeared = true
            } else {
                withAnimation(.spring(duration: 1.0).delay(0.2)) { modelAppeared = true }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设置").font(WDFont.title(30)).foregroundStyle(WDColor.ricePaper)
            Rectangle().fill(WDColor.amber).frame(width: 40, height: 2.5)
        }
        .padding(.top, 8)
    }

    private var settingsGroup: some View {
        InkCard {
            VStack(spacing: 0) {
                row(icon: "heart.text.square", title: "Apple Health 授权",
                    value: healthAccessValue) {
                    requestAppleHealthAccess()
                }
                Divider().overlay(WDColor.mist.opacity(0.12)).padding(.vertical, 4)
                row(icon: "bell.badge", title: "通知权限", value: "去设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                Divider().overlay(WDColor.mist.opacity(0.12)).padding(.vertical, 4)
                row(icon: "location", title: "定位权限", value: "去设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private var healthAccessValue: String {
        if isRequestingHealth { return "请求中" }
        switch session.planning.healthKit.authorizationState {
        case .notDetermined: return "连接"
        case .requesting: return "请求中"
        case .unavailable: return "此设备不可用"
        case .denied: return "授权失败"
        case .granted:
            let count = (session.latestHealthSnapshot ?? session.planning.healthSnapshot)?.readings.count ?? 0
            return count > 0 ? "已读取 \(count) 项" : "已请求 · 无数据"
        }
    }

    private func requestAppleHealthAccess() {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        Task {
            let snapshot = await session.connectAppleHealth()
            isRequestingHealth = false

            if session.planning.healthKit.authorizationState == .unavailable {
                healthResultMessage = "当前设备不支持 HealthKit。请使用已登录 Apple ID 的真实 iPhone 测试。"
            } else if let error = session.planning.healthKit.lastError,
                      session.planning.healthKit.authorizationState == .denied {
                healthResultMessage = "HealthKit 授权失败：\(error)"
            } else if let snapshot, !snapshot.readings.isEmpty {
                healthResultMessage = "已从 Apple Health 读取 \(snapshot.readings.count) 项健康指标。"
            } else {
                healthResultMessage = "权限请求已完成，但没有可读数据。请打开“健康”App → 右上角头像 → 隐私 → App → WUDAX，开启需要读取的健康类别，并确认健康 App 中已有相关数据。"
            }
            showHealthResult = true
        }
    }

    private var voiceGroup: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(WDColor.ink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent 语音")
                            .font(WDFont.heading(16))
                            .foregroundStyle(WDColor.ricePaper)
                        Text(agentVoiceStatusText)
                            .font(WDFont.caption(11))
                            .foregroundStyle(WDColor.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                VStack(spacing: 0) {
                    toggleRow(icon: "mic", title: "语音输入",
                              subtitle: "把你说的话转成当前行程 Agent 的问题",
                              isOn: sessionAgentVoiceInputBinding)
                    Divider().overlay(WDColor.mist.opacity(0.12)).padding(.vertical, 4)
                    toggleRow(icon: "speaker.wave.2", title: "朗读回复",
                              subtitle: "Agent 回答后用系统中文语音本地播报",
                              isOn: sessionAgentSpokenRepliesBinding)
                    Divider().overlay(WDColor.mist.opacity(0.12)).padding(.vertical, 4)
                    toggleRow(icon: "bell.and.waves.left.and.right", title: "主动式 AI 播报",
                              subtitle: "风险、偏航、进度等主动提醒可直接出声",
                              isOn: sessionAgentProactiveSpeechBinding)
                    Divider().overlay(WDColor.mist.opacity(0.12)).padding(.vertical, 4)
                    row(icon: "gearshape", title: "语音权限", value: "系统设置") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private var exoskeletonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WUDAX 膝关节外骨骼")
                        .font(WDFont.heading(17))
                        .foregroundStyle(WDColor.ricePaper)
                    Label("拖动旋转 · 双指缩放", systemImage: "rotate.3d")
                        .font(WDFont.caption(11))
                        .foregroundStyle(WDColor.mist)
                }
                Spacer()
                Text(modelLoadState == false ? "资源异常" : "设备数据尚未连接")
                    .font(WDFont.caption(10).weight(.semibold))
                    .foregroundStyle(modelLoadState == false ? WDColor.amber : WDColor.mist)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(WDColor.mossSurface.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(WDColor.line.opacity(0.55), lineWidth: 1)
                    )

                ExoModelView(loadState: $modelLoadState, reduceMotion: reduceMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .opacity(modelAppeared && modelLoadState != false ? 1 : 0)
                    .scaleEffect(reduceMotion || modelAppeared ? 1 : 0.92)

                if modelLoadState == false {
                    VStack(spacing: 10) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(WDColor.amber)
                        Text("3D 模型资源未能加载")
                            .font(WDFont.body(14).weight(.medium))
                            .foregroundStyle(WDColor.ricePaper)
                        Text("权限与其他设置仍可正常使用")
                            .font(WDFont.caption(11))
                            .foregroundStyle(WDColor.mist)
                    }
                }
            }
            .frame(height: 320)
            .accessibilityLabel(modelLoadState == false ? "外骨骼 3D 模型加载失败" : "可交互的 WUDAX 膝关节外骨骼 3D 模型")
            .accessibilityHint("单指拖动旋转，双指缩放")
        }
    }

    private func row(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundStyle(WDColor.bamboo).frame(width: 24)
                Text(title).font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                Spacer()
                Text(value).font(WDFont.caption()).foregroundStyle(WDColor.mist)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(WDColor.mist.opacity(0.6))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(WDColor.bamboo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(WDFont.body(15)).foregroundStyle(WDColor.ricePaper)
                Text(subtitle).font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(WDColor.ink)
        }
        .padding(.vertical, 8)
    }

    private var agentVoiceStatusText: String {
        "本机语音输入优先走离线识别；没有权限或设备不支持时，仍保留文字输入。"
    }

    private var sessionAgentVoiceInputBinding: Binding<Bool> {
        Binding(
            get: { sessionAgent.voicePreferences.voiceInputEnabled },
            set: { newValue in
                guard sessionAgent.voicePreferences.voiceInputEnabled != newValue else { return }
                sessionAgent.toggleVoiceInput()
            }
        )
    }

    private var sessionAgentSpokenRepliesBinding: Binding<Bool> {
        Binding(
            get: { sessionAgent.voicePreferences.spokenRepliesEnabled },
            set: { newValue in
                guard sessionAgent.voicePreferences.spokenRepliesEnabled != newValue else { return }
                sessionAgent.toggleSpokenReplies()
            }
        )
    }

    private var sessionAgentProactiveSpeechBinding: Binding<Bool> {
        Binding(
            get: { sessionAgent.voicePreferences.proactiveSpeechEnabled },
            set: { newValue in
                guard sessionAgent.voicePreferences.proactiveSpeechEnabled != newValue else { return }
                sessionAgent.toggleProactiveSpeech()
            }
        )
    }

    private var aboutCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("关于 WUDAX").font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper)
                Text("品牌内核「无待」——平时安静,关键时刻主动。端侧离线运行,你的数据留在设备上。")
                    .font(WDFont.caption()).foregroundStyle(WDColor.mist)
            }
        }
    }
}
