import SwiftUI

@main
struct LaxPocketApp: App {
    @State private var store: AppStore
    @State private var cloud: CloudStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        #if DEBUG
        // `-demo` (e.g. `xcrun simctl launch booted com.princa.laxpocket -demo`) loads the made-up demo athlete.
        if ProcessInfo.processInfo.arguments.contains("-demo") { store.loadDemoAthlete() }
        #endif
        _store = State(initialValue: store)
        _cloud = State(initialValue: CloudStore(appStore: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(cloud)
                .onOpenURL { url in Task { await cloud.handleRedirect(url) } }
                // Cloud sync shows the notice itself, and an alert can't appear over its sheet anyway.
                .alert("Cloud sync", isPresented: Binding(get: { cloud.authNotice != nil && !cloud.isShowingCloudSync },
                                                          set: { if !$0 { cloud.authNotice = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(cloud.authNotice ?? "")
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await cloud.syncNow() } }
        }
    }
}
