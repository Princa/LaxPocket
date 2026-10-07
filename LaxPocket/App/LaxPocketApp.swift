import SwiftUI
import LaxPocketCore

@main
struct LaxPocketApp: App {
    @State private var store: AppStore
    @State private var cloud: CloudStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        let cloud = CloudStore(appStore: store)
        #if DEBUG
        // `-demo` (e.g. `xcrun simctl launch booted com.princa.laxpocket -demo`) loads the made-up demo athlete,
        // `-demo-as parent|athlete|coach|mentalCoach` loads her as that account would see her in the cloud, and
        // `-demo-sport hockey` opens her hockey profile (and a coach's hockey roster) instead of lacrosse.
        let arguments = ProcessInfo.processInfo.arguments
        let sport = arguments.firstIndex(of: "-demo-sport").flatMap { $0 + 1 < arguments.count ? Sport(rawValue: arguments[$0 + 1]) : nil }
            ?? .lacrosse
        if let index = arguments.firstIndex(of: "-demo-as"), index + 1 < arguments.count,
           let viewer = Relationship(rawValue: arguments[index + 1]) {
            cloud.loadDemo(viewer: viewer, sport: sport)
        } else if arguments.contains("-demo") || arguments.contains("-demo-sport") {
            cloud.loadDemo(viewer: nil, sport: sport)
        }
        #endif
        _store = State(initialValue: store)
        _cloud = State(initialValue: cloud)
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
