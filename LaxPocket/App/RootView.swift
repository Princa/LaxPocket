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

    var body: some View {
        @Bindable var store = store
        let theme = AppTheme(palette: store.palette)
        TabView(selection: $store.selectedTab) {
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
            NavigationStack { BudgetView() }
                .tabItem { Label("Budget", systemImage: "wallet.pass") }
                .tag(AppTab.budget)
        }
        .tint(theme.primary)
        .environment(\.appTheme, theme)
        .preferredColorScheme(.light)
    }
}
