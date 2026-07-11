import SwiftUI

// MARK: - 地图相机控制按钮组(行中页与主地图页共用)
// 「路线聚焦」+「定位循环」:定位按钮第一次点进入概览(路线与自己一屏收进),
// 再点切换为跟随(放大到自己),继续点在两者间循环 —— 两个页面的样式、
// 点击逻辑与动画过渡完全一致;相机动画由 RouteMapView.updateCamera 统一执行。

/// 定位按钮的循环:任意状态先进概览,概览与跟随之间往复。
enum LocationFocusCycle {
    static func next(after mode: RouteMapCameraMode) -> RouteMapCameraMode {
        switch mode {
        case .automatic, .route: return .overview
        case .overview: return .user
        case .user: return .overview
        }
    }
}

struct MapCameraControls: View {
    @Binding var cameraMode: RouteMapCameraMode
    @Binding var cameraRequestID: Int
    /// 点定位按钮时的附加动作(主地图页用来启动定位监听)。
    var onLocateTapped: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            MapControlButton(icon: "arrow.up.left.and.arrow.down.right",
                             selected: cameraMode == .route) {
                cameraMode = .route
                cameraRequestID += 1
                Haptics.tap()
            }
            .accessibilityLabel("路线聚焦")

            MapControlButton(icon: "location.fill",
                             selected: cameraMode != .route) {
                onLocateTapped?()
                cameraMode = LocationFocusCycle.next(after: cameraMode)
                cameraRequestID += 1
                Haptics.tap()
            }
            .accessibilityLabel("定位:概览与跟随循环切换")
        }
    }
}

/// 圆形地图控制按钮(与行中页原样式一致)。
struct MapControlButton: View {
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? WDColor.onDark : WDColor.ricePaper)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(selected ? WDColor.ink : WDColor.deepMoss.opacity(0.96))
                        .overlay(Circle().stroke(WDColor.line.opacity(selected ? 0 : 0.8), lineWidth: 1))
                        .shadow(color: WDColor.ink.opacity(0.12), radius: 8, y: 4)
                )
        }
        .buttonStyle(.plain)
    }
}
