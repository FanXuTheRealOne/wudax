import SwiftUI

@main
struct WudaXApp: App {
    @StateObject private var session = TripSession()
    @StateObject private var library = RouteLibraryStore()
    @StateObject private var navigation = AppNavigation()
    /// 全局唯一的行中智能体:跨 session 存活,每次行程在其内部开独立 context。
    @StateObject private var agent = WudaXAgent()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(library)
                .environmentObject(navigation)
                .environmentObject(agent)
                .environmentObject(agent.llm)   // 首页 ChatView 与 agent 共享同一模型容器
                .preferredColorScheme(.light)
                .onAppear {
                    session.library = library
                    agent.attach(session)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: TripSession

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            ContourBackground().ignoresSafeArea()

            switch session.phase {
            case .home:
                RootTabView()
                    .transition(.opacity)
            case .planningChat:
                PlanningChatView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .budgetCard:
                BudgetCardView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .inTrip:
                TripDashboardView()
                    .transition(.opacity)
            case .review:
                ReviewView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: phaseKey)
    }

    private var phaseKey: Int {
        switch session.phase {
        case .home: 0
        case .planningChat: 1
        case .budgetCard: 2
        case .inTrip: 3
        case .review: 4
        }
    }
}
