import SwiftUI
import LaxPocketCore

/// Sign in to Supabase, see sync status, bring athletes down from the cloud and share them.
struct CloudSyncView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudStore.self) private var cloud
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var showShare = false
    @State private var pendingCloudDelete: ProfileRow?

    var body: some View {
        Form {
            if !cloud.isConfigured {
                notConfigured
            } else if let session = cloud.session {
                signedIn(session)
            } else {
                signInForm
            }
        }
        .navigationTitle("Cloud sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) { ShareAthleteView(summary: store.data.summary) }
        .confirmationDialog("Delete \(pendingCloudDelete?.firstName ?? "this athlete") from the cloud?",
                            isPresented: Binding(get: { pendingCloudDelete != nil }, set: { if !$0 { pendingCloudDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingCloudDelete) { row in
            Button("Delete from the cloud", role: .destructive) { Task { await cloud.deleteFromCloud(row.id) } }
        } message: { _ in
            Text("Removes the athlete and all their data from your cloud account and anyone it was shared with. Copies already on a phone stay there.")
        }
    }

    // MARK: - States

    private var notConfigured: some View {
        Section {
            Label("Not set up in this build", systemImage: "icloud.slash")
            Text("Add Supabase.plist with your project's URL and anon key to the app, then rebuild. See docs/supabase.md in the repository.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.ink2)
        } footer: {
            Text("Until then, everything stays on this iPhone.")
        }
    }

    @ViewBuilder
    private var signInForm: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
        } header: {
            Text("LaxPocket account")
        } footer: {
            Text("Back up every athlete on this iPhone and keep them in sync across phones. Sign in with the same account on each phone, or share an athlete with another account.")
        }

        Section {
            Button {
                run { try await cloud.signIn(email: email, password: password) }
            } label: {
                HStack {
                    Text("Sign in")
                    if isWorking { Spacer(); ProgressView() }
                }
            }
            .disabled(!canSubmit)
            Button("Create an account") {
                run {
                    if try await cloud.signUp(email: email, password: password) {
                        message = "Check \(email) for a confirmation link, then come back and sign in."
                    }
                }
            }
            .disabled(!canSubmit)
        } footer: {
            if let message { Text(message) }
        }
    }

    @ViewBuilder
    private func signedIn(_ session: AuthSession) -> some View {
        Section {
            LabeledContent("Account", value: session.email ?? "Signed in")
            HStack {
                Text("Status")
                Spacer()
                if cloud.isSyncing {
                    ProgressView()
                } else if let error = cloud.lastError {
                    Text(error).foregroundStyle(.red).multilineTextAlignment(.trailing)
                } else if let date = cloud.lastSynced {
                    Text("Synced \(date.formatted(.relative(presentation: .named)))").foregroundStyle(AppTheme.muted)
                } else {
                    Text("Not synced yet").foregroundStyle(AppTheme.muted)
                }
            }
            Button("Sync now") { Task { await cloud.syncNow() } }
                .disabled(cloud.isSyncing)
        } footer: {
            Text("Every athlete on this iPhone syncs automatically after changes and when the app opens. If the same thing was changed on two phones, this iPhone’s version is kept.")
        }

        if !cloud.remoteOnly.isEmpty {
            Section {
                ForEach(cloud.remoteOnly, id: \.id) { row in
                    HStack {
                        ProfileAvatar(summary: ProfileSummary(id: row.id, name: row.firstName, themeID: row.themeID), size: 32)
                        Text(row.firstName.isEmpty ? "Unnamed athlete" : row.firstName)
                        Spacer()
                        Button("Download") { Task { await cloud.download(row.id) } }
                            .buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingCloudDelete = row }
                    }
                }
            } header: {
                Text("In the cloud, not on this iPhone")
            } footer: {
                Text("Swipe to delete an athlete from the cloud.")
            }
        }

        Section {
            Button { showShare = true } label: {
                Label("Share \(store.data.summary.displayName) with another account", systemImage: "person.badge.plus")
            }
        } footer: {
            Text("For a parent’s or coach’s phone with its own account. They need to create their account first.")
        }

        Section {
            Button("Sign out", role: .destructive) { Task { await cloud.signOut() } }
        } footer: {
            Text("Athletes stay on this iPhone after signing out.")
        }
    }

    private var canSubmit: Bool {
        !isWorking && email.contains("@") && password.count >= 6
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        message = nil
        Task {
            do {
                try await action()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Gives another LaxPocket account access to one athlete.
struct ShareAthleteView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let summary: ProfileSummary
    @State private var email = ""
    @State private var canEdit = true
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Their account email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Can make changes", isOn: $canEdit)
                } footer: {
                    Text(canEdit ? "They can log sessions, results, events and expenses for \(summary.displayName)."
                                 : "They can see \(summary.displayName)’s data but not change it.")
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Share \(summary.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Share", action: share).fontWeight(.bold).disabled(!email.contains("@"))
                    }
                }
            }
        }
    }

    private func share() {
        isWorking = true
        message = nil
        Task {
            do {
                try await cloud.share(summary.id, with: email, canEdit: canEdit)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
