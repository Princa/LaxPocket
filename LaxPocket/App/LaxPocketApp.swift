import SwiftUI

@main
struct LaxPocketApp: App {
    @State private var store: AppStore
    @State private var cloud: CloudStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _cloud = State(initialValue: CloudStore(appStore: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(cloud)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await cloud.syncNow() } }
        }
    }
}
