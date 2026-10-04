import SwiftUI
import LaxPocketCore

/// First launch: no athlete profiles yet.
struct WelcomeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(CloudStore.self) private var cloud
    #if DEBUG
    @Environment(AppStore.self) private var store
    #endif
    @State private var showNew = false
    @State private var showCloud = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Wordmark(theme: theme)
                Spacer()
                Eyebrow(text: "Welcome", color: theme.onPrimary)
                Text("One place for the whole season")
                    .font(.display(44))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("Training hours, combine results, games, the budget and mental-game docs. Start by adding an athlete.")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.onPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.primary.ignoresSafeArea(edges: .top))

            VStack(alignment: .leading, spacing: 14) {
                Label("Add a profile for each athlete in the family. Their data stays separate.", systemImage: "person.2")
                Label(cloud.isConfigured ? "Stored on this iPhone, with optional cloud sync." : "Everything is stored on this iPhone.", systemImage: "lock")
                Button { showNew = true } label: {
                    Label("Create an athlete profile", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                .padding(.top, 6)
                if cloud.isConfigured {
                    Button("Have an account or an invite code? Sign in") { showCloud = true }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                #if DEBUG
                Button("Load the demo athlete") { store.loadDemoAthlete() }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                #endif
            }
            .font(.system(size: 14))
            .foregroundStyle(AppTheme.ink2)
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea(edges: .bottom))
        }
        .sheet(isPresented: $showNew) { NewProfileView() }
        .sheet(isPresented: $showCloud) {
            NavigationStack {
                CloudSyncView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showCloud = false } }
                    }
            }
        }
    }
}
