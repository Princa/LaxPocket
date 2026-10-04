import SwiftUI
import LaxPocketCore

enum AppTab: Hashable {
    case home
    case training
    case metrics
    case events
    case budget
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudStore.self) private var cloud

    var body: some View {
        let theme = AppTheme(palette: store.palette)
        Group {
            if store.hasProfile && cloud.isCoaching && store.showsCoaching {
                // A parent who also coaches: Home's athlete menu switches here, and My family switches back.
                NavigationStack { CoachingView(onShowFamily: { store.showsCoaching = false }) }
            } else if store.hasProfile {
                tabs
            } else if cloud.isCoaching {
                // A coach with no athletes of their own: Coaching is the whole app.
                NavigationStack { CoachingView(showsSettings: true) }
            } else {
                WelcomeView()
            }
        }
        .tint(theme.primary)
        .environment(\.appTheme, theme)
        .preferredColorScheme(.light)
    }

    private var tabs: some View {
        @Bindable var store = store
        return TabView(selection: $store.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            NavigationStack { TrainingView() }
                .tabItem { Label("Training", systemImage: "stopwatch") }
                .tag(AppTab.training)
            NavigationStack { MetricsView() }
                .tabItem { Label("Metrics", systemImage: "waveform.path.ecg") }
                .tag(AppTab.metrics)
            NavigationStack { EventsView() }
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(AppTab.events)
            // A coach doesn't see the family's budget.
            if store.data.canRead(.budget) {
                NavigationStack { BudgetView() }
                    .tabItem { Label("Budget", systemImage: "wallet.pass") }
                    .tag(AppTab.budget)
            }
        }
        // A fresh set of screens per athlete, so no screen keeps state from the previous profile.
        .id(store.data.id)
    }
}
