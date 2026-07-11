import SwiftUI
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

/// 首页浏览壳:自定义底部 Tab bar(行程 / 地图 / 数据 / 设置)。
/// 只在 .home 相位显示;进入规划/行程/复盘等流程时由 RootView 整屏切换。
struct RootTabView: View {
    @EnvironmentObject var navigation: AppNavigation

    var body: some View {
        ZStack(alignment: .bottom) {
            selectedContent
                .id(navigation.selectedTab)
                .transition(.opacity.combined(with: .scale(scale: 0.995)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            WudaXTabBar(
                selection: Binding(
                    get: { navigation.selectedTab },
                    set: { navigation.selectedTab = $0 }
                )
            )
            .frame(height: 84)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch navigation.selectedTab {
        case .trips: HomeView()
        case .map: MapTabView()
        case .data: DataTabView()
        case .settings: SettingsTabView()
        }
    }
}

private struct WudaXTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var glassNamespace
    @State private var dragOriginIndex: Int?
    @State private var dragTranslation: CGFloat = 0

    private let tabs = AppTab.allCases

    var body: some View {
        GeometryReader { geometry in
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                liquidGlassBar(width: geometry.size.width)
            } else {
                fallbackBar(width: geometry.size.width)
            }
#else
            fallbackBar(width: geometry.size.width)
#endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主导航")
    }

#if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func liquidGlassBar(width: CGFloat) -> some View {
        GlassEffectContainer(spacing: 8) {
            barContent(width: width - 14) {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(WDColor.bamboo.opacity(0.20)).interactive(),
                        in: .rect(cornerRadius: 27)
                    )
                    .glassEffectID("selected-tab", in: glassNamespace)
            }
            .padding(7)
            .glassEffect(.regular, in: .rect(cornerRadius: 34))
        }
    }
#endif

    private func fallbackBar(width: CGFloat) -> some View {
        barContent(width: width - 14) {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(WDColor.mossSurface.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .stroke(.white.opacity(0.72), lineWidth: 0.8)
                )
                .shadow(color: WDColor.ink.opacity(0.10), radius: 10, y: 4)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(WDColor.deepMoss.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.76), lineWidth: 0.8)
                )
                .shadow(color: WDColor.ink.opacity(0.14), radius: 20, y: 8)
        )
    }

    private func barContent<Indicator: View>(
        width: CGFloat,
        @ViewBuilder indicator: () -> Indicator
    ) -> some View {
        let itemWidth = max(width / CGFloat(tabs.count), 1)
        let selectedIndex = tabs.firstIndex(of: selection) ?? 0
        let originIndex = dragOriginIndex ?? selectedIndex
        let rawPosition = CGFloat(originIndex) * itemWidth + dragTranslation
        let indicatorX = min(max(rawPosition, 0), itemWidth * CGFloat(tabs.count - 1))

        return ZStack(alignment: .leading) {
            indicator()
                .frame(width: max(itemWidth - 4, 1), height: 66)
                .offset(x: indicatorX + 2)

            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    tabButton(tab, width: itemWidth)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .simultaneousGesture(tabDragGesture(itemWidth: itemWidth))
    }

    private func tabButton(_ tab: AppTab, width: CGFloat) -> some View {
        let isSelected = selection == tab
        return Button {
            select(tab)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 23, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.title)
                    .font(WDFont.caption(11).weight(isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? WDColor.bamboo : WDColor.ricePaper.opacity(0.78))
            .frame(width: width, height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tabDragGesture(itemWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .local)
            .onChanged { value in
                let startIndex = dragOriginIndex ?? (tabs.firstIndex(of: selection) ?? 0)
                if dragOriginIndex == nil { dragOriginIndex = startIndex }
                dragTranslation = value.translation.width

                let targetIndex = clampedIndex(
                    Int((CGFloat(startIndex) + value.translation.width / itemWidth).rounded())
                )
                let target = tabs[targetIndex]
                if target != selection {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = target
                    }
                    Haptics.tap()
                }
            }
            .onEnded { value in
                let startIndex = dragOriginIndex ?? (tabs.firstIndex(of: selection) ?? 0)
                let targetIndex = clampedIndex(
                    Int((CGFloat(startIndex) + value.predictedEndTranslation.width / itemWidth).rounded())
                )
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    selection = tabs[targetIndex]
                    dragOriginIndex = nil
                    dragTranslation = 0
                }
                Haptics.tap()
            }
    }

    private func select(_ tab: AppTab) {
        guard tab != selection else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            selection = tab
            dragOriginIndex = nil
            dragTranslation = 0
        }
        Haptics.tap()
    }

    private func clampedIndex(_ index: Int) -> Int {
        min(max(index, 0), tabs.count - 1)
    }
}
