import SwiftUI

@main
struct WudaXApp: App {
    @StateObject private var session = TripSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
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
                HomeView()
                    .transition(.opacity)
            case .planningChat:
                PlanningChatView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .budgetCard:
                BudgetCardView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .gate:
                GatekeeperView()
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
        case .gate: 3
        case .inTrip: 4
        case .review: 5
        }
    }
}
