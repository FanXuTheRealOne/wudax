import SwiftUI

/// 首页浏览壳:自定义底部 Tab bar(行程 / 地图 / 数据 / 设置)。
/// 只在 .home 相位显示;进入规划/行程/复盘等流程时由 RootView 整屏切换。
struct RootTabView: View {
    @State private var tab: Tab = .trips

    enum Tab: CaseIterable {
        case trips, map, data, settings
        var title: String {
            switch self {
            case .trips: "行程"; case .map: "地图"; case .data: "数据"; case .settings: "设置"
            }
        }
        var icon: String {
            switch self {
            case .trips: "mountain.2"; case .map: "map"; case .data: "chart.bar.xaxis"; case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .trips: HomeView()
                case .map: MapTabView()
                case .data: DataTabView()
                case .settings: SettingsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .ignoresSafeArea(.keyboard)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { tab = item }
                    Haptics.tap()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: tab == item ? .semibold : .regular))
                        Text(item.title).font(WDFont.caption(10))
                    }
                    .foregroundStyle(tab == item ? WDColor.amber : WDColor.mist)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 26)
        .padding(.horizontal, 8)
        .background(
            WDColor.deepMoss.opacity(0.96)
                .overlay(Rectangle().fill(WDColor.mist.opacity(0.12)).frame(height: 0.5), alignment: .top)
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
