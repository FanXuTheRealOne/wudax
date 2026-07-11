import SwiftUI
import UIKit
import Combine

/// 首页、底部导航和地图模块之间共享的轻量导航状态。
/// 历史路线从首页进入地图时，先选中对应路线，再切换到地图 Tab。
enum AppTab: CaseIterable, Hashable {
    case trips, map, data, settings

    var title: String {
        switch self {
        case .trips: "行程"
        case .map: "地图"
        case .data: "数据"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .trips: "mountain.2"
        case .map: "map"
        case .data: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var selectedTab: AppTab = .trips
    @Published var selectedMapRouteID: UUID?

    func showRouteOnMap(_ record: RouteRecord) {
        selectedMapRouteID = record.id
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            selectedTab = .map
        }
    }
}

/// 使用系统 TabView/UITabBar 承载顶层导航。
/// iOS 26 由系统自动采用 Liquid Glass；旧系统保持原生材质与无障碍行为。
struct RootTabView: View {
    @EnvironmentObject var navigation: AppNavigation

    private var selection: Binding<AppTab> {
        Binding(
            get: { navigation.selectedTab },
            set: { navigation.selectedTab = $0 }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            HomeView()
                .tag(AppTab.trips)
                .tabItem { Label(AppTab.trips.title, systemImage: AppTab.trips.icon) }

            MapTabView()
                .tag(AppTab.map)
                .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.icon) }

            DataTabView()
                .tag(AppTab.data)
                .tabItem { Label(AppTab.data.title, systemImage: AppTab.data.icon) }

            SettingsTabView()
                .tag(AppTab.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
        }
        .tint(WDColor.bamboo)
        .background(NativeTabBarScrubInstaller(selection: selection))
        .ignoresSafeArea(.keyboard)
    }
}

/// 为原生 UITabBar 增加横向滑过选择，同时不替换系统点击、布局和 Liquid Glass 渲染。
private struct NativeTabBarScrubInstaller: UIViewControllerRepresentable {
    @Binding var selection: AppTab

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIViewController(context: Context) -> TabBarLocatorViewController {
        let controller = TabBarLocatorViewController()
        controller.onTabBarLocated = { [weak coordinator = context.coordinator] tabBar in
            coordinator?.install(on: tabBar)
        }
        return controller
    }

    func updateUIViewController(_ controller: TabBarLocatorViewController, context: Context) {
        context.coordinator.selection = $selection
        controller.locateTabBarWhenReady()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var selection: Binding<AppTab>
        private weak var installedTabBar: UITabBar?
        private var panGesture: UIPanGestureRecognizer?
        private let feedback = UISelectionFeedbackGenerator()

        init(selection: Binding<AppTab>) {
            self.selection = selection
        }

        func install(on tabBar: UITabBar) {
            style(tabBar)
            guard installedTabBar !== tabBar else { return }

            if let panGesture, let installedTabBar {
                installedTabBar.removeGestureRecognizer(panGesture)
            }

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delegate = self
            tabBar.addGestureRecognizer(pan)
            installedTabBar = tabBar
            panGesture = pan
        }

        private func style(_ tabBar: UITabBar) {
            tabBar.tintColor = UIColor(WDColor.bamboo)
            tabBar.unselectedItemTintColor = UIColor(WDColor.mist)
            tabBar.isTranslucent = true

            if #available(iOS 26.0, *) {
                // 不设置自定义背景，让系统完整接管 Liquid Glass、对比度和透明度偏好。
            } else {
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.backgroundColor = UIColor(WDColor.deepMoss).withAlphaComponent(0.94)
                appearance.shadowColor = UIColor(WDColor.line)
                tabBar.standardAppearance = appearance
                tabBar.scrollEdgeAppearance = appearance
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let tabBar = installedTabBar,
                  let items = tabBar.items,
                  items.count == AppTab.allCases.count,
                  tabBar.bounds.width > 0 else { return }

            if gesture.state == .began { feedback.prepare() }
            guard gesture.state == .began || gesture.state == .changed else { return }

            let locationX = min(max(gesture.location(in: tabBar).x, 0), tabBar.bounds.width - 1)
            let itemWidth = tabBar.bounds.width / CGFloat(items.count)
            let index = min(max(Int(locationX / itemWidth), 0), AppTab.allCases.count - 1)
            let target = AppTab.allCases[index]

            guard target != selection.wrappedValue else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                selection.wrappedValue = target
            }
            feedback.selectionChanged()
            feedback.prepare()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: installedTabBar)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private final class TabBarLocatorViewController: UIViewController {
    var onTabBarLocated: ((UITabBar) -> Void)?

    override func loadView() {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        locateTabBarWhenReady()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        locateTabBarWhenReady()
    }

    func locateTabBarWhenReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let tabBar = tabBarController?.tabBar {
                onTabBarLocated?(tabBar)
                return
            }
            guard let root = view.window?.rootViewController,
                  let tabBarController = findTabBarController(in: root) else { return }
            onTabBarLocated?(tabBarController.tabBar)
        }
    }

    private func findTabBarController(in controller: UIViewController) -> UITabBarController? {
        if let tabBarController = controller as? UITabBarController { return tabBarController }
        for child in controller.children {
            if let match = findTabBarController(in: child) { return match }
        }
        if let presented = controller.presentedViewController {
            return findTabBarController(in: presented)
        }
        return nil
    }
}
