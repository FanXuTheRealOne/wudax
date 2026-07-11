import SwiftUI
import UIKit

/// 「设置」Tab —— 外骨骼 3D 展示、健康授权入口、关于。
struct SettingsTabView: View {
    @EnvironmentObject var session: TripSession
    @State private var showExo = false
    @State private var isRequestingHealth = false
    @State private var showHealthResult = false
    @State private var healthResultMessage = ""

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            ContourBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    // 外骨骼 3D —— 从首页迁移到这里
                    Button { showExo = true } label: {
                        InkCard {
                            HStack(spacing: 14) {
                                Group {
                                    if let ui = UIImage(named: "exo_thumb") {
                                        Image(uiImage: ui).resizable().scaledToFit()
                                    } else {
                                        Image(systemName: "figure.walk.motion")
                                            .font(.system(size: 26, weight: .light)).foregroundStyle(WDColor.amber)
                                    }
                                }
                                .frame(width: 54, height: 54)
                                .background(RoundedRectangle(cornerRadius: 12).fill(WDColor.mossSurface))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("WUDAX 膝关节外骨骼").font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                                    Text("v2.0 数据接入预留 · 查看 3D 模型").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(WDColor.mist)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    settingsGroup

                    aboutCard
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showExo) { ExoShowcaseView() }
        .alert("Apple Health", isPresented: $showHealthResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(healthResultMessage)
        }
        .task {
            await session.refreshAppleHealthAccess()
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
