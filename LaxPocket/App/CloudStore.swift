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
    /// Athletes on this iPhone that this account used to sync but can't any more: the owner took this account off them,
    /// or deleted them from the cloud.
    private(set) var noLongerShared: Set<UUID> = []
    /// The signed-in account's name and whether it's a parent, athlete or coach. Nil until loaded or set up.
    private(set) var account: AccountRow?
    /// True once it's known that the signed-in account hasn't said who it is yet.
    private(set) var needsAccountSetup = false
    /// The rosters this account coaches.
    private(set) var rosters: [RosterRow] = []

    /// Shows the Coaching workspace: the account is a coach or mental coach, or already has a roster.
    var isCoaching: Bool {
        #if DEBUG
        if demoRosters != nil { return true }
        #endif
        return isSignedIn && (!rosters.isEmpty || account.map { [.coach, .mentalCoach].contains($0.kind) } == true)
    }

    #if DEBUG
    /// Made-up rosters (Theme & settings → Demo data) shown in Coaching instead of the cloud's. Debug builds only;
    /// never saved, and gone when the app restarts.
    private(set) var demoRosters: [CoachRoster]?

    /// Previews Coaching with a made-up team or mental-game roster for `sport`, or stops when `kind` is nil.
    func showDemoCoaching(_ kind: RosterKind?, sport: Sport = .lacrosse) {
        demoRosters = kind.map { DemoSeason.coachRosters(kind: $0, sport: sport) }
    }

    /// Loads Maya as `viewer` would see her in the cloud (nil: just this phone, as before), showing her `sport` profile,
    /// and, for a coach or mental coach, opens Coaching with a made-up roster for that sport.
    func loadDemo(viewer: Relationship?, sport: Sport = .lacrosse) {
        appStore.loadDemoAthlete(viewer: viewer, sport: sport)
        switch viewer {
        case .coach: showDemoCoaching(.team, sport: sport)
        case .mentalCoach: showDemoCoaching(.mental, sport: sport)
        default: showDemoCoaching(nil)
        }
        appStore.showsCoaching = demoRosters != nil
    }
    #endif

    /// Changing a made-up roster would go to the cloud, so the preview refuses.
    private func refuseDemoChanges() throws {
        #if DEBUG
        if demoRosters != nil { throw DemoOnlyError() }
        #endif
    }
    /// What happened when the app was opened from a confirmation email; shown once, then cleared.
    var authNotice: String?
    /// True while Cloud sync is on screen, which shows `authNotice` itself.
    var isShowingCloudSync = false

    @ObservationIgnored private let appStore: AppStore
    @ObservationIgnored private var client: SupabaseClient?
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var syncAgain = false
    /// Right after signing in on a phone with no athletes, bring everything down.
    @ObservationIgnored private var downloadAllOnNextSync = false

    private static let sessionAccount = "session"

    /// Where the confirmation email's link sends people once their email is confirmed: back into the app
    /// (the `laxpocket` URL scheme in project.yml). Supabase only uses it if it's listed under
    /// Authentication → URL Configuration → Redirect URLs.
    nonisolated static let authRedirectURL = URL(string: "laxpocket://auth-callback")!

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
        switch try await client.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
                                       redirectTo: CloudStore.authRedirectURL) {
        case .signedIn(let newSession):
            sessionChanged(newSession)
            lastError = nil
            await syncNow()
            return false
        case .confirmEmail:
            return true
        }
    }

    func resendConfirmation(email: String) async throws {
        try await client?.resendConfirmation(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                             redirectTo: CloudStore.authRedirectURL)
    }

    /// Opens the link from a confirmation email: signs in to the new account and syncs.
    func handleRedirect(_ url: URL) async {
        guard let client, url.scheme == CloudStore.authRedirectURL.scheme, url.host == CloudStore.authRedirectURL.host else { return }
        if let current = session {
            // Switching accounts here would leave this account's sync records behind; signing out clears them.
            authNotice = "This iPhone is signed in as \(current.email ?? "another account"). To use the new account, sign out in Cloud sync, then sign in with it."
            return
        }
        do {
            let newSession = try await client.signIn(fromRedirect: url)
            sessionChanged(newSession)
            lastError = nil
            downloadAllOnNextSync = appStore.profiles.isEmpty
            authNotice = "Email confirmed. You’re signed in as \(newSession.email ?? "your new account") and your athletes are syncing."
            await syncNow()
        } catch CloudError.server(_, "otp_expired", _) {
            authNotice = "That confirmation link has expired or was already used. Try signing in; if your email isn’t confirmed yet, tap Resend confirmation email."
        } catch {
            authNotice = "Couldn’t finish signing in: \(error.localizedDescription)"
        }
    }

    /// Signs out. The athletes stay on this iPhone; the sync records are cleared so a later sign-in starts fresh.
    func signOut() async {
        pendingSync?.cancel()
        await client?.signOut()
        sessionChanged(nil)
        for profile in appStore.profiles { try? appStore.library.removeSyncBase(profile.id) }
        remoteOnly = []
        noLongerShared = []
        account = nil
        needsAccountSetup = false
        rosters = []
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
            // One athlete failing (say, one with an edit the cloud refuses) doesn’t hold up the rest.
            // The demo athlete (debug builds) stays on this iPhone. An athlete's first profile goes up before the sports
            // added to it, which the cloud checks against it.
            let ordered = appStore.profiles.filter { $0.athleteID == nil } + appStore.profiles.filter { $0.athleteID != nil }
            for summary in ordered where !summary.isDemo && !noLongerShared.contains(summary.id) {
                do {
                    try await sync(summary.id, using: cloud)
                } catch {
                    // It synced before and the cloud no longer shows it to this account, so uploading it again was refused.
                    if case CloudError.server(_, "42501", _) = error, appStore.library.loadSyncBase(summary.id) != nil,
                       case .some(.none) = try? await cloud.snapshot(profileID: summary.id) {
                        noLongerShared.insert(summary.id)
                        continue
                    }
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
                if account == nil { await loadAccount(using: cloud) }
                if let mine = try? await cloud.rosters() { rosters = mine }
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
        let base = appStore.library.loadSyncBase(id)
        var merged = try await cloud.sync(local: captured, base: base)
        // A sport just added for an athlete gets the family on the athlete's other sports.
        if base == nil, merged.profile.athleteID != nil, merged.access?.role == .owner {
            do {
                try await cloud.addFamilyToSport(profileID: id)
                merged.access = try await cloud.snapshot(profileID: id)?.access ?? merged.access
            } catch {
                print("LaxPocket: could not bring the family to \(captured.summary.nameWithSport) – \(error)")
            }
        }

        // The profile may have been edited or removed while the sync was running.
        guard appStore.profiles.contains(where: { $0.id == id }), let current = appStore.profileData(id) else { return }
        try appStore.library.saveSyncBase(merged, for: id)
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

    /// Takes an athlete this account lost access to off this iPhone.
    func removeFromThisPhone(_ id: UUID) {
        try? appStore.library.removeSyncBase(id)
        appStore.deleteProfile(id)
        noLongerShared.remove(id)
    }

    // MARK: - Account and people

    private func loadAccount(using cloud: CloudSync) async {
        guard let userID = session?.userID else { return }
        do {
            account = try await cloud.account(userID: userID)
            needsAccountSetup = account == nil
        } catch {
            print("LaxPocket: couldn't load the account – \(error)")
        }
    }

    /// Saves who the signed-in account is: the name others on an athlete see, and parent, athlete or coach.
    func saveAccount(name: String, kind: Relationship) async throws {
        guard let client, let userID = session?.userID else { return }
        let row = AccountRow(userID: userID, displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
        try await CloudSync(client: client).saveAccount(row)
        account = row
        needsAccountSetup = false
    }

    func people(on id: UUID) async throws -> [ProfilePerson] {
        guard let client else { return [] }
        return try await CloudSync(client: client).people(profileID: id, me: session?.userID)
    }

    func openInvites(for id: UUID) async throws -> [InviteRow] {
        guard let client else { return [] }
        return try await CloudSync(client: client).openInvites(profileID: id)
    }

    /// Makes an invite code for an athlete. The athlete is synced first, so it's in the cloud to be joined.
    func invite(to id: UUID, as relationship: Relationship) async throws -> String {
        guard let client else { throw CloudError.notSignedIn }
        await syncNow()
        return try await CloudSync(client: client).createInvite(profileID: id, relationship: relationship)
    }

    func cancelInvite(_ code: String) async throws {
        guard let client else { return }
        try await CloudSync(client: client).cancelInvite(code: code)
    }

    /// Takes someone off an athlete (owner only). Family comes off every sport.
    func remove(_ userID: UUID, from id: UUID) async throws {
        guard let client else { return }
        try await CloudSync(client: client).removeMember(profileID: id, userID: userID)
    }

    /// Takes this account off an athlete it doesn't own, and the athlete off this iPhone. Family leaves every sport.
    func leave(_ id: UUID) async throws {
        guard let client, let userID = session?.userID else { return }
        let removed = try await CloudSync(client: client).removeMember(profileID: id, userID: userID)
        for profileID in Set(removed + [id]) where appStore.profiles.contains(where: { $0.id == profileID }) {
            removeFromThisPhone(profileID)
        }
    }

    /// Joins an athlete with an invite code, brings them onto this iPhone, every sport a parent or the athlete is
    /// given, and switches to them.
    func join(code: String) async throws {
        guard let client else { throw CloudError.notSignedIn }
        let cloud = CloudSync(client: client)
        let id = try await cloud.acceptInvite(code: code)
        noLongerShared.remove(id)
        try await download(id, using: cloud)
        let key = appStore.profileData(id)?.athleteKey ?? id
        let local = Set(appStore.profiles.map(\.id))
        for row in try await cloud.profiles() where row.athleteKey == key && !local.contains(row.id) {
            noLongerShared.remove(row.id)
            try await download(row.id, using: cloud)
        }
        remoteOnly.removeAll { $0.athleteKey == key }
        appStore.switchProfile(to: id)
    }

    // MARK: - Codes and coaches

    /// What a code is for, before using it.
    func describe(code: String) async throws -> CodeInfo {
        guard let client else { throw CloudError.notSignedIn }
        return try await CloudSync(client: client).describeCode(code)
    }

    /// Adds an athlete on this iPhone to a coach's roster. The athlete is synced first, so it's in the cloud.
    func addToRoster(code: String, athlete id: UUID) async throws {
        guard let client else { throw CloudError.notSignedIn }
        await syncNow()
        _ = try await CloudSync(client: client).joinRoster(code: code, profileID: id)
    }

    func coaches(of id: UUID) async throws -> [AthleteCoachRow] {
        guard let client else { return [] }
        return try await CloudSync(client: client).athleteCoaches(profileID: id)
    }

    func removeFromRoster(_ rosterID: UUID, athlete id: UUID) async throws {
        try refuseDemoChanges()
        guard let client else { return }
        try await CloudSync(client: client).removeFromRoster(rosterID: rosterID, profileID: id)
    }

    func setMentalCoachTrust(athlete id: UUID, coach coachID: UUID, trusted: Bool) async throws {
        guard let client else { return }
        try await CloudSync(client: client).setMentalCoachTrust(profileID: id, coachID: coachID, trusted: trusted)
    }

    // MARK: - Coaching

    /// Every roster with what this account can see of each athlete, read fresh from the cloud.
    func coachWorkspace() async throws -> [CoachRoster] {
        #if DEBUG
        if let demoRosters { return demoRosters }
        #endif
        guard let client else { throw CloudError.notSignedIn }
        let workspace = try await CloudSync(client: client).coachWorkspace()
        rosters = workspace.map { RosterRow(id: $0.id, kind: $0.kind, name: $0.name, joinCode: $0.joinCode, sport: $0.sport) }
        return workspace
    }

    func createRoster(name: String, kind: RosterKind, sport: Sport) async throws {
        try refuseDemoChanges()
        guard let client else { throw CloudError.notSignedIn }
        let cloud = CloudSync(client: client)
        _ = try await cloud.createRoster(name: name, kind: kind, sport: sport)
        rosters = try await cloud.rosters()
    }

    func renameRoster(_ id: UUID, to name: String) async throws {
        try refuseDemoChanges()
        guard let client else { return }
        try await CloudSync(client: client).renameRoster(id, to: name)
    }

    /// A new code (the old one stops working), or none to close the roster to new athletes.
    func resetRosterCode(_ id: UUID, open: Bool) async throws -> String? {
        try refuseDemoChanges()
        guard let client else { return nil }
        return try await CloudSync(client: client).resetRosterCode(id, open: open)
    }

    /// Gives a task, or changes one.
    func saveAssignment(_ assignment: Assignment) async throws {
        try refuseDemoChanges()
        guard let client else { throw CloudError.notSignedIn }
        try await CloudSync(client: client).saveAssignment(assignment)
    }

    func deleteAssignment(_ id: UUID) async throws {
        try refuseDemoChanges()
        guard let client else { return }
        try await CloudSync(client: client).deleteAssignment(id)
    }

    /// Writes this coach's note on an athlete's game; an empty note removes it.
    func saveCoachNote(event eventID: UUID, athlete id: UUID, note: String) async throws {
        try refuseDemoChanges()
        guard let client else { throw CloudError.notSignedIn }
        try await CloudSync(client: client).saveCoachNote(eventID: eventID, profileID: id, note: note)
    }

    func deleteRoster(_ id: UUID) async throws {
        try refuseDemoChanges()
        guard let client else { return }
        try await CloudSync(client: client).deleteRoster(id)
        rosters.removeAll { $0.id == id }
    }

    /// Lets another SportsPocket account see (or also edit) an athlete.
    func share(_ id: UUID, with email: String, canEdit: Bool) async throws {
        guard let client else { return }
        // The athlete has to be in the cloud before it can be shared.
        await syncNow()
        try await CloudSync(client: client).share(profileID: id, email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  role: canEdit ? .editor : .viewer)
    }
}

/// A change to the made-up demo rosters, which the preview doesn't make.
struct DemoOnlyError: LocalizedError {
    var errorDescription: String? { "This is demo data, so changes aren’t saved." }
}
