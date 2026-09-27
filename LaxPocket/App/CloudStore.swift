import Foundation
import Observation
import LaxPocketCore

/// Signs in to Supabase and keeps the athletes on this iPhone in sync with the cloud.
///
/// Data stays local-first: the app works offline, and a sync runs after edits (a few seconds later),
/// when the app comes to the foreground, and from Cloud sync → Sync now.
@MainActor
@Observable
final class CloudStore {
    /// Nil until `Supabase.plist` is added to the app (see docs/supabase.md).
    let config: SupabaseConfig?
    private(set) var session: AuthSession?
    private(set) var isSyncing = false
    private(set) var lastSynced: Date?
    private(set) var lastError: String?
    /// Athletes in the cloud that aren't on this iPhone.
    private(set) var remoteOnly: [ProfileRow] = []

    @ObservationIgnored private let appStore: AppStore
    @ObservationIgnored private var client: SupabaseClient?
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var syncAgain = false
    /// Right after signing in on a phone with no athletes, bring everything down.
    @ObservationIgnored private var downloadAllOnNextSync = false

    private static let sessionAccount = "session"

    init(appStore: AppStore, config: SupabaseConfig? = CloudStore.bundledConfig) {
        self.appStore = appStore
        self.config = config
        if let config {
            let saved = Keychain.data(for: CloudStore.sessionAccount).flatMap { try? JSONDecoder().decode(AuthSession.self, from: $0) }
            session = saved
            client = makeClient(config, session: saved)
        }
        appStore.onLocalChange = { [weak self] _ in self?.scheduleSync() }
    }

    var isConfigured: Bool { config != nil }
    var isSignedIn: Bool { session != nil }

    /// Reads Supabase.plist from the app bundle.
    nonisolated static var bundledConfig: SupabaseConfig? {
        guard let url = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        return SupabaseConfig(values: values)
    }

    private func makeClient(_ config: SupabaseConfig, session: AuthSession?) -> SupabaseClient {
        SupabaseClient(config: config, session: session, onSessionChange: { [weak self] newSession in
            Task { @MainActor [weak self] in self?.sessionChanged(newSession) }
        })
    }

    private func sessionChanged(_ newSession: AuthSession?) {
        session = newSession
        Keychain.set(newSession.flatMap { try? JSONEncoder().encode($0) }, for: CloudStore.sessionAccount)
    }

    // MARK: - Account

    func signIn(email: String, password: String) async throws {
        guard let client else { return }
        let newSession = try await client.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        sessionChanged(newSession)
        lastError = nil
        downloadAllOnNextSync = appStore.profiles.isEmpty
        await syncNow()
    }

    /// Returns true when the project wants the new account to confirm its email first.
    func signUp(email: String, password: String) async throws -> Bool {
        guard let client else { return false }
        switch try await client.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) {
        case .signedIn(let newSession):
            sessionChanged(newSession)
            lastError = nil
            await syncNow()
            return false
        case .confirmEmail:
            return true
        }
    }

    /// Signs out. The athletes stay on this iPhone; the sync records are cleared so a later sign-in starts fresh.
    func signOut() async {
        pendingSync?.cancel()
        await client?.signOut()
        sessionChanged(nil)
        for profile in appStore.profiles { try? appStore.library.removeSyncBase(profile.id) }
        remoteOnly = []
        lastSynced = nil
        lastError = nil
    }

    // MARK: - Sync

    /// Syncs a few seconds after the last local change, so a burst of edits goes up together.
    func scheduleSync() {
        guard isSignedIn else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Syncs every athlete on this iPhone and refreshes the list of athletes only in the cloud.
    func syncNow() async {
        guard let client, isSignedIn else { return }
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            let cloud = CloudSync(client: client)
            var firstError: Error?
            // One athlete failing (say, a view-only one with local edits) doesn't hold up the rest.
            for summary in appStore.profiles {
                do {
                    try await sync(summary.id, using: cloud)
                } catch {
                    firstError = firstError ?? error
                    print("LaxPocket: sync of \(summary.displayName) failed – \(error)")
                }
            }
            do {
                let local = Set(appStore.profiles.map(\.id))
                remoteOnly = try await cloud.profiles().filter { !local.contains($0.id) }
                if downloadAllOnNextSync {
                    downloadAllOnNextSync = false
                    for row in remoteOnly { try await download(row.id, using: cloud) }
                    remoteOnly = []
                }
                if let firstError { throw firstError }
                lastSynced = Date()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                print("LaxPocket: sync failed – \(error)")
            }
        } while syncAgain
    }

    private func sync(_ id: UUID, using cloud: CloudSync) async throws {
        guard let captured = appStore.profileData(id) else { return }
        let merged = try await cloud.sync(local: captured, base: appStore.library.loadSyncBase(id))
        try appStore.library.saveSyncBase(merged, for: id)

        // The profile may have been edited or removed while the sync was running.
        guard appStore.profiles.contains(where: { $0.id == id }), let current = appStore.profileData(id) else { return }
        let result = current == captured
            ? merged
            : ProfileMerge.merge(base: ProfileSnapshot(captured), local: ProfileSnapshot(current), remote: merged).merged
        if !result.hasSameRows(as: ProfileSnapshot(current)) {
            appStore.replaceProfileData(result.appData)
        }
    }

    /// Brings an athlete from the cloud onto this iPhone.
    func download(_ id: UUID) async {
        guard let client else { return }
        do {
            try await download(id, using: CloudSync(client: client))
            remoteOnly.removeAll { $0.id == id }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func download(_ id: UUID, using cloud: CloudSync) async throws {
        guard let snapshot = try await cloud.snapshot(profileID: id) else { return }
        try appStore.library.saveSyncBase(snapshot, for: id)
        appStore.replaceProfileData(snapshot.appData)
    }

    /// Removes an athlete from the cloud (owner only). Copies already on phones stay there.
    func deleteFromCloud(_ id: UUID) async {
        guard let client else { return }
        do {
            try await CloudSync(client: client).deleteProfile(id)
            try? appStore.library.removeSyncBase(id)
            remoteOnly.removeAll { $0.id == id }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Lets another LaxPocket account see (or also edit) an athlete.
    func share(_ id: UUID, with email: String, canEdit: Bool) async throws {
        guard let client else { return }
        // The athlete has to be in the cloud before it can be shared.
        await syncNow()
        try await CloudSync(client: client).share(profileID: id, email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  role: canEdit ? .editor : .viewer)
    }
}
