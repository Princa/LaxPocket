import Foundation

/// Reads and writes athlete profiles in Supabase.
///
/// A sync is local-first: the device keeps working offline, and each sync
/// 1. reads the profile's rows from the cloud,
/// 2. merges them with this device's data and what the cloud held last time (`ProfileMerge`),
/// 3. writes only the rows that changed here.
///
/// Writes aren't one transaction, but they're safe to repeat: if a sync stops halfway, the next one
/// sees which rows already arrived and sends the rest.
public struct CloudSync: Sendable {
    public let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Profiles this account can see: its own and any shared with it.
    public func profiles() async throws -> [ProfileRow] {
        try await client.select(ProfileRow.table, order: "created_at.asc")
    }

    /// Everything the cloud holds for a profile, or nil if the profile isn't there (or isn't shared with this account).
    public func snapshot(profileID: UUID) async throws -> ProfileSnapshot? {
        let id = profileID.uuidString.lowercased()
        let byID = [URLQueryItem(name: "id", value: "eq.\(id)")]
        let byProfile = [URLQueryItem(name: "profile_id", value: "eq.\(id)")]
        guard let profile = try await client.select(ProfileRow.table, filters: byID, order: "id", as: ProfileRow.self).first else {
            return nil
        }
        let programs = try await client.select(ProgramRow.table, filters: byProfile, order: "sort_order,id", as: ProgramRow.self)
        let sessions = try await client.select(SessionRow.table, filters: byProfile, order: "id", as: SessionRow.self)
        let results = try await client.select(CombineResultRow.table, filters: byProfile, order: "id", as: CombineResultRow.self)
        let measurements = try await client.select(CombineMeasurementRow.table, filters: byProfile, order: "result_id,metric", as: CombineMeasurementRow.self)
        let events = try await client.select(EventRow.table, filters: byProfile, order: "id", as: EventRow.self)
        let stats = try await client.select(GameStatsRow.table, filters: byProfile, order: "event_id", as: GameStatsRow.self)
        let reflections = try await client.select(ReflectionRow.table, filters: byProfile, order: "event_id", as: ReflectionRow.self)
        let focus = try await client.select(FocusGoalRow.table, filters: byProfile, order: "event_id,position,id", as: FocusGoalRow.self)
        let videos = try await client.select(VideoRow.table, filters: byProfile, order: "event_id,position,id", as: VideoRow.self)
        let checklist = try await client.select(ChecklistItemRow.table, filters: byProfile, order: "event_id,position,id", as: ChecklistItemRow.self)
        let expenses = try await client.select(ExpenseRow.table, filters: byProfile, order: "id", as: ExpenseRow.self)
        let docs = try await client.select(MentalDocRow.table, filters: byProfile, order: "id", as: MentalDocRow.self)
        let body = try await client.select(BodyMeasurementRow.table, filters: byProfile, order: "id", as: BodyMeasurementRow.self)
        let drills = try await client.select(WallballDrillRow.table, filters: byProfile, order: "sort_order,id", as: WallballDrillRow.self)
        let wallball = try await client.select(WallballSessionRow.table, filters: byProfile, order: "id", as: WallballSessionRow.self)
        let wallballSets = try await client.select(WallballSetRow.table, filters: byProfile, order: "session_id,position,drill_id,hand", as: WallballSetRow.self)
        let seasonBudgets = try await client.select(SeasonBudgetRow.table, filters: byProfile, order: "season", as: SeasonBudgetRow.self)
        let programBudgets = try await client.select(ProgramBudgetRow.table, filters: byProfile, order: "season,program_id", as: ProgramBudgetRow.self)
        let trips = try await client.select(TripRow.table, filters: byProfile, order: "departs_at,id", as: TripRow.self)
        let lockedDocs = try await client.select(LockedMentalDocRow.table, filters: byProfile, order: "id", as: LockedMentalDocRow.self)
        let access = try await client.select(MemberRow.mine, filters: byProfile, order: "profile_id", as: MemberRow.self).first?.access

        return ProfileSnapshot.assemble(profile: profile, programs: programs, sessions: sessions, results: results, measurements: measurements,
                                        events: events, stats: stats, reflections: reflections, focus: focus, videos: videos,
                                        checklist: checklist, expenses: expenses, docs: docs, bodyMeasurements: body,
                                        wallballDrills: drills, wallballSessions: wallball, wallballSets: wallballSets,
                                        seasonBudgets: seasonBudgets, programBudgets: programBudgets, trips: trips,
                                        lockedDocs: lockedDocs, access: access)
    }

    /// Writes changes for one profile. Parents go before children and deletes go last, so foreign keys hold at every step.
    public func push(_ changes: SyncChanges) async throws {
        if let profile = changes.profile { try await client.upsert([profile]) }
        let byProfile = [URLQueryItem(name: "profile_id", value: "eq.\(changes.profileID.uuidString.lowercased())")]

        try await client.upsert(changes.seasonBudgets.upserts)
        try await client.upsert(changes.programs.upserts)
        try await client.upsert(changes.programBudgets.upserts)
        try await client.upsert(changes.sessions.upserts)

        // A changed testing day replaces its measurements.
        let results = changes.combineResults.upserts
        try await client.upsert(results.map(\.result))
        try await client.delete(CombineMeasurementRow.table, where: "result_id", in: results.map { $0.id.uuidString.lowercased() }, filters: byProfile)
        try await client.upsert(results.flatMap(\.measurements))

        // A changed event replaces its stats, reflection, goals, videos and checklist.
        let events = changes.events.upserts
        let eventIDs = events.map { $0.id.uuidString.lowercased() }
        try await client.upsert(events.map(\.event))
        try await client.upsert(events.compactMap(\.stats))
        try await client.delete(GameStatsRow.table, where: "event_id", in: events.filter { $0.stats == nil }.map { $0.id.uuidString.lowercased() }, filters: byProfile)
        try await client.upsert(events.compactMap(\.reflection))
        try await client.delete(ReflectionRow.table, where: "event_id", in: events.filter { $0.reflection == nil }.map { $0.id.uuidString.lowercased() }, filters: byProfile)
        try await client.delete(FocusGoalRow.table, where: "event_id", in: eventIDs, filters: byProfile)
        try await client.upsert(events.flatMap(\.focus))
        try await client.delete(VideoRow.table, where: "event_id", in: eventIDs, filters: byProfile)
        try await client.upsert(events.flatMap(\.videos))
        try await client.delete(ChecklistItemRow.table, where: "event_id", in: eventIDs, filters: byProfile)
        try await client.upsert(events.flatMap(\.checklist))

        // Trips after programs and events, which they point at, and before the expenses that point at them.
        try await client.upsert(changes.trips.upserts)
        try await client.upsert(changes.expenses.upserts)
        try await client.upsert(changes.docs.upserts)
        try await client.upsert(changes.bodyMeasurements.upserts)

        // A changed wall ball session replaces its sets.
        try await client.upsert(changes.wallballDrills.upserts)
        let wallball = changes.wallballSessions.upserts
        try await client.upsert(wallball.map(\.session))
        try await client.delete(WallballSetRow.table, where: "session_id", in: wallball.map { $0.id.uuidString.lowercased() }, filters: byProfile)
        try await client.upsert(wallball.flatMap(\.sets))

        func ids(_ keys: [UUID]) -> [String] { keys.map { $0.uuidString.lowercased() } }
        try await client.delete(SessionRow.table, where: "id", in: ids(changes.sessions.deletes), filters: byProfile)
        try await client.delete(CombineResultRow.table, where: "id", in: ids(changes.combineResults.deletes), filters: byProfile)
        try await client.delete(EventRow.table, where: "id", in: ids(changes.events.deletes), filters: byProfile)
        try await client.delete(ExpenseRow.table, where: "id", in: ids(changes.expenses.deletes), filters: byProfile)
        try await client.delete(TripRow.table, where: "id", in: ids(changes.trips.deletes), filters: byProfile)
        try await client.delete(MentalDocRow.table, where: "id", in: ids(changes.docs.deletes), filters: byProfile)
        try await client.delete(BodyMeasurementRow.table, where: "id", in: ids(changes.bodyMeasurements.deletes), filters: byProfile)
        try await client.delete(WallballSessionRow.table, where: "id", in: ids(changes.wallballSessions.deletes), filters: byProfile)
        try await client.delete(WallballDrillRow.table, where: "id", in: changes.wallballDrills.deletes, filters: byProfile)
        try await client.delete(SeasonBudgetRow.table, where: "season", in: changes.seasonBudgets.deletes.map(String.init), filters: byProfile)
        for (programID, keys) in Dictionary(grouping: changes.programBudgets.deletes, by: \.programID).sorted(by: { $0.key < $1.key }) {
            try await client.delete(ProgramBudgetRow.table, where: "season", in: keys.map { String($0.season) },
                                    filters: byProfile + [URLQueryItem(name: "program_id", value: "eq.\(programID)")])
        }
        // Programs last: sessions that pointed at them are gone by now.
        try await client.delete(ProgramRow.table, where: "id", in: changes.programs.deletes, filters: byProfile)
    }

    /// Syncs one profile. Returns what the cloud holds afterwards, which is also the profile's new local data
    /// and the base for the next sync.
    public func sync(local: AppData, base: ProfileSnapshot?) async throws -> ProfileSnapshot {
        let remote = try await snapshot(profileID: local.id)
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: remote)
        if !outcome.changes.isEmpty { try await push(outcome.changes) }
        return outcome.merged
    }

    /// Removes a profile and everything under it from the cloud. Only its owner can.
    public func deleteProfile(_ id: UUID) async throws {
        let deleted = try await client.delete(ProfileRow.table, where: "id", in: [id.uuidString.lowercased()])
        if deleted == 0 {
            throw CloudError.server(status: 403, code: "42501", message: "Only the athlete’s owner can delete them from the cloud.")
        }
    }

    public enum ShareRole: String, Sendable {
        case editor
        case viewer
    }

    /// Gives another LaxPocket account access to a profile, as a parent. The other person has to have signed up already.
    public func share(profileID: UUID, email: String, role: ShareRole) async throws {
        _ = try await client.rpc("share_profile", params: [
            "p_profile_id": profileID.uuidString.lowercased(),
            "p_email": email,
            "p_role": role.rawValue
        ])
    }

    // MARK: - Accounts, people and invites

    /// The account's name and what it is, or nil before it's set up.
    public func account(userID: UUID) async throws -> AccountRow? {
        try await client.select(AccountRow.table, filters: [URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())")],
                                order: "user_id", as: AccountRow.self).first
    }

    public func saveAccount(_ account: AccountRow) async throws {
        try await client.upsert([account])
    }

    /// Everyone on an athlete, owner first, with the names they set up their accounts with.
    public func people(profileID: UUID, me: UUID?) async throws -> [ProfilePerson] {
        let byProfile = [URLQueryItem(name: "profile_id", value: "eq.\(profileID.uuidString.lowercased())")]
        let members = try await client.select(MemberRow.table, filters: byProfile, order: "created_at,user_id", as: MemberRow.self)
        let ids = members.compactMap(\.userID).map { SupabaseClient.quoted($0.uuidString.lowercased()) }
        let accounts = ids.isEmpty ? [] : try await client.select(
            AccountRow.table, filters: [URLQueryItem(name: "user_id", value: "in.(\(ids.joined(separator: ",")))")], order: "user_id", as: AccountRow.self)
        let names = Dictionary(accounts.map { ($0.userID, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        return members.compactMap { m in
            m.userID.map { ProfilePerson(userID: $0, name: names[$0] ?? "", access: m.access, isMe: $0 == me) }
        }
        .sorted { ($0.access.role == .owner ? 0 : 1) < ($1.access.role == .owner ? 0 : 1) }
    }

    /// Invite codes for an athlete that haven't been used and haven't expired. Owner only; others get none.
    public func openInvites(profileID: UUID, now: Date = Date()) async throws -> [InviteRow] {
        let filters = [URLQueryItem(name: "profile_id", value: "eq.\(profileID.uuidString.lowercased())"),
                       URLQueryItem(name: "accepted_at", value: "is.null")]
        return try await client.select(InviteRow.table, filters: filters, order: "created_at.desc", as: InviteRow.self)
            .filter { $0.isOpen(now: now) }
    }

    /// Makes a code that links whoever enters it to the athlete. Owner only.
    public func createInvite(profileID: UUID, relationship: Relationship) async throws -> String {
        let data = try await client.rpc("create_profile_invite", params: [
            "p_profile_id": profileID.uuidString.lowercased(),
            "p_relationship": relationship.rawValue
        ])
        return try JSONDecoder().decode(String.self, from: data)
    }

    /// Links this account to the athlete an invite code is for, and returns the athlete's id.
    public func acceptInvite(code: String) async throws -> UUID {
        let data = try await client.rpc("accept_profile_invite", params: ["p_code": code])
        return try JSONDecoder().decode(UUID.self, from: data)
    }

    public func cancelInvite(code: String) async throws {
        try await client.delete(InviteRow.table, where: "code", in: [code])
    }

    /// Takes someone off an athlete (owner only), or this account off one it doesn't own.
    public func removeMember(profileID: UUID, userID: UUID) async throws {
        let deleted = try await client.delete(MemberRow.table, where: "user_id", in: [userID.uuidString.lowercased()],
                                              filters: [URLQueryItem(name: "profile_id", value: "eq.\(profileID.uuidString.lowercased())")])
        if deleted == 0 {
            throw CloudError.server(status: 403, code: "42501", message: "Only the athlete’s owner can remove people.")
        }
    }
}

// MARK: - Coaches

extension CloudSync {
    /// What a code is for, before using it: an invite to an athlete, or a coach's roster.
    public func describeCode(_ code: String) async throws -> CodeInfo {
        try SupabaseClient.decoder.decode(CodeInfo.self, from: await client.rpc("describe_code", params: ["p_code": code]))
    }

    /// Adds an athlete to the roster with this code (owner or parent only). Returns the roster's id.
    public func joinRoster(code: String, profileID: UUID) async throws -> UUID {
        let data = try await client.rpc("join_roster", params: ["p_code": code, "p_profile_id": profileID.uuidString.lowercased()])
        return try JSONDecoder().decode(UUID.self, from: data)
    }

    /// The rosters an athlete is on and their coaches.
    public func athleteCoaches(profileID: UUID) async throws -> [AthleteCoachRow] {
        let data = try await client.rpc("athlete_coaches", params: ["p_profile_id": profileID.uuidString.lowercased()])
        return try SupabaseClient.decoder.decode([AthleteCoachRow].self, from: data)
    }

    /// Takes an athlete off a roster: the coach, or the athlete's owner or parent, can.
    public func removeFromRoster(rosterID: UUID, profileID: UUID) async throws {
        let deleted = try await client.delete(RosterAthleteRow.table, where: "profile_id", in: [profileID.uuidString.lowercased()],
                                              filters: [URLQueryItem(name: "roster_id", value: "eq.\(rosterID.uuidString.lowercased())")])
        if deleted == 0 {
            throw CloudError.server(status: 403, code: "42501", message: "Only the coach or a parent can take the athlete off this roster.")
        }
    }

    private struct TrustParams: Encodable, Sendable {
        var p_profile_id: UUID
        var p_coach_id: UUID
        var p_trusted: Bool
    }

    /// The athlete's login lets a mental coach open the docs it locked, or stops letting them.
    public func setMentalCoachTrust(profileID: UUID, coachID: UUID, trusted: Bool) async throws {
        _ = try await client.rpc("set_mental_coach_trust", encoded: TrustParams(p_profile_id: profileID, p_coach_id: coachID, p_trusted: trusted))
    }

    public func createRoster(name: String, kind: RosterKind) async throws -> UUID {
        let data = try await client.rpc("create_roster", params: ["p_name": name, "p_kind": kind.rawValue])
        return try JSONDecoder().decode(UUID.self, from: data)
    }

    public func renameRoster(_ id: UUID, to name: String) async throws {
        _ = try await client.rpc("rename_roster", params: ["p_roster_id": id.uuidString.lowercased(), "p_name": name])
    }

    private struct CodeParams: Encodable, Sendable {
        var p_roster_id: UUID
        var p_open: Bool
    }

    /// A new code for the roster (the old one stops working), or none when `open` is false.
    public func resetRosterCode(_ id: UUID, open: Bool) async throws -> String? {
        let data = try await client.rpc("reset_roster_code", encoded: CodeParams(p_roster_id: id, p_open: open))
        return try JSONDecoder().decode(String?.self, from: data)
    }

    public func deleteRoster(_ id: UUID) async throws {
        try await client.delete(RosterRow.table, where: "id", in: [id.uuidString.lowercased()])
    }

    /// The signed-in account's rosters, oldest first.
    public func rosters() async throws -> [RosterRow] {
        try await client.select(RosterRow.table, order: "created_at", as: RosterRow.self)
    }

    /// Every roster the signed-in account coaches, with what it can see of each athlete since `CoachRoster.since(now:)`
    /// and events from the last month on. Read straight from the cloud; nothing is kept on the phone.
    public func coachWorkspace(now: Date = Date(), calendar: Calendar = .laxWeek) async throws -> [CoachRoster] {
        let rosters = try await rosters()
        guard !rosters.isEmpty else { return [] }
        let places: [RosterAthleteRow] = try await select(RosterAthleteRow.table, where: "roster_id",
                                                          in: rosters.map(\.id.uuidString), order: "created_at")
        let ids = Array(Set(places.map(\.profileID))).map { $0.uuidString.lowercased() }.sorted()
        guard !ids.isEmpty else { return CoachWorkspace.assemble(rosters: rosters, places: [], rows: .init()) }

        let since = Timestamp(CoachRoster.since(now: now, calendar: calendar)).description
        let eventsSince = Timestamp(calendar.date(byAdding: .day, value: -CoachRoster.recentEventDays, to: now) ?? now).description
        var rows = CoachWorkspace.Rows()
        rows.profiles = try await select(CoachAthleteProfileRow.table, where: "id", in: ids, order: "id")
        rows.programs = try await select(ProgramRow.table, where: "profile_id", in: ids, order: "sort_order,id")
        rows.sessions = try await select(SessionRow.table, where: "profile_id", in: ids,
                                         filters: [URLQueryItem(name: "started_at", value: "gte.\(since)")], order: "id")
        rows.wallballDrills = try await select(WallballDrillRow.table, where: "profile_id", in: ids, order: "sort_order,id")
        rows.wallballSessions = try await select(WallballSessionRow.table, where: "profile_id", in: ids,
                                                 filters: [URLQueryItem(name: "done_at", value: "gte.\(since)")], order: "id")
        rows.wallballSets = try await select(WallballSetRow.table, where: "session_id", in: rows.wallballSessions.map(\.id.uuidString),
                                             order: "session_id,position,drill_id,hand")
        rows.events = try await select(EventRow.table, where: "profile_id", in: ids,
                                       filters: [URLQueryItem(name: "starts_at", value: "gte.\(eventsSince)")], order: "id")
        let eventIDs = rows.events.map(\.id.uuidString)
        rows.stats = try await select(GameStatsRow.table, where: "event_id", in: eventIDs, order: "event_id")
        rows.reflections = try await select(ReflectionRow.table, where: "event_id", in: eventIDs, order: "event_id")
        rows.focus = try await select(FocusGoalRow.table, where: "event_id", in: eventIDs, order: "event_id,position,id")
        // Empty for a team coach: the cloud only gives mental docs to those who see the mental game.
        rows.docs = try await select(MentalDocRow.table, where: "profile_id", in: ids, order: "id")
        rows.lockedDocs = try await select(LockedMentalDocRow.table, where: "profile_id", in: ids, order: "id")
        return CoachWorkspace.assemble(rosters: rosters, places: places, rows: rows)
    }

    /// Rows where `column` is one of `values`, a hundred values per request so the URL stays short.
    private func select<Row: Decodable>(_ table: String, where column: String, in values: [String], filters: [URLQueryItem] = [],
                                        order: String) async throws -> [Row] {
        var rows: [Row] = []
        for start in stride(from: 0, to: values.count, by: 100) {
            let list = values[start..<min(start + 100, values.count)].map { SupabaseClient.quoted($0.lowercased()) }.joined(separator: ",")
            rows += try await client.select(table, filters: filters + [URLQueryItem(name: column, value: "in.(\(list))")], order: order, as: Row.self)
        }
        return rows
    }
}

/// Groups what a coach reads from the cloud into rosters of athletes.
enum CoachWorkspace {
    struct Rows {
        var profiles: [CoachAthleteProfileRow] = []
        var programs: [ProgramRow] = []
        var sessions: [SessionRow] = []
        var wallballDrills: [WallballDrillRow] = []
        var wallballSessions: [WallballSessionRow] = []
        var wallballSets: [WallballSetRow] = []
        var events: [EventRow] = []
        var stats: [GameStatsRow] = []
        var reflections: [ReflectionRow] = []
        var focus: [FocusGoalRow] = []
        var docs: [MentalDocRow] = []
        var lockedDocs: [LockedMentalDocRow] = []
    }

    static func assemble(rosters: [RosterRow], places: [RosterAthleteRow], rows: Rows) -> [CoachRoster] {
        func byProfile<Row>(_ list: [Row], _ key: (Row) -> UUID) -> [UUID: [Row]] { Dictionary(grouping: list, by: key) }
        let programs = byProfile(rows.programs, \.profileID), sessions = byProfile(rows.sessions, \.profileID)
        let drills = byProfile(rows.wallballDrills, \.profileID), wallball = byProfile(rows.wallballSessions, \.profileID)
        let sets = byProfile(rows.wallballSets, \.profileID), events = byProfile(rows.events, \.profileID)
        let stats = byProfile(rows.stats, \.profileID), reflections = byProfile(rows.reflections, \.profileID)
        let focus = byProfile(rows.focus, \.profileID), docs = byProfile(rows.docs, \.profileID)
        let locked = byProfile(rows.lockedDocs, \.profileID)
        let kindsByProfile = Dictionary(grouping: places, by: \.profileID).mapValues { list in
            Set(list.compactMap { place in rosters.first { $0.id == place.rosterID }?.kind.relationship })
        }

        var athletes: [UUID: CoachAthlete] = [:]
        for profile in rows.profiles {
            let id = profile.id
            let snapshot = ProfileSnapshot.assemble(
                profile: profile.profileRow, programs: programs[id] ?? [], sessions: sessions[id] ?? [], results: [], measurements: [],
                events: events[id] ?? [], stats: stats[id] ?? [], reflections: reflections[id] ?? [], focus: focus[id] ?? [],
                videos: [], checklist: [], expenses: [], docs: docs[id] ?? [], bodyMeasurements: [], wallballDrills: drills[id] ?? [],
                wallballSessions: wallball[id] ?? [], wallballSets: sets[id] ?? [], lockedDocs: locked[id] ?? [],
                access: ProfileAccess(role: .viewer, relationships: kindsByProfile[id] ?? []))
            athletes[id] = CoachAthlete(data: snapshot.appData)
        }
        return rosters.map { roster in
            let onRoster = places.filter { $0.rosterID == roster.id }.compactMap { athletes[$0.profileID] }
            return CoachRoster(id: roster.id, name: roster.name, kind: roster.kind, joinCode: roster.joinCode,
                               athletes: onRoster.sorted { $0.data.profile.firstName.localizedCaseInsensitiveCompare($1.data.profile.firstName) == .orderedAscending })
        }
    }
}

/// Someone on an athlete, for the People list.
public struct ProfilePerson: Hashable, Identifiable, Sendable {
    public var userID: UUID
    /// Blank until they set up their account.
    public var name: String
    public var access: ProfileAccess
    public var isMe: Bool

    public var id: UUID { userID }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if isMe { return trimmed.isEmpty ? "You" : "\(trimmed) (you)" }
        return trimmed.isEmpty ? "LaxPocket account" : trimmed
    }
}

extension ProfileSnapshot {
    /// Groups flat table rows back into a snapshot.
    static func assemble(profile: ProfileRow, programs: [ProgramRow], sessions: [SessionRow], results: [CombineResultRow],
                         measurements: [CombineMeasurementRow], events: [EventRow], stats: [GameStatsRow], reflections: [ReflectionRow],
                         focus: [FocusGoalRow], videos: [VideoRow], checklist: [ChecklistItemRow], expenses: [ExpenseRow],
                         docs: [MentalDocRow], bodyMeasurements: [BodyMeasurementRow], wallballDrills: [WallballDrillRow] = [],
                         wallballSessions: [WallballSessionRow] = [], wallballSets: [WallballSetRow] = [],
                         seasonBudgets: [SeasonBudgetRow] = [], programBudgets: [ProgramBudgetRow] = [], trips: [TripRow] = [],
                         lockedDocs: [LockedMentalDocRow] = [], access: ProfileAccess? = nil) -> ProfileSnapshot {
        let metricOrder = Dictionary(uniqueKeysWithValues: CombineMetric.allCases.enumerated().map { ($1, $0) })
        let measurementsByResult = Dictionary(grouping: measurements, by: \.resultID)
        let statsByEvent = Dictionary(stats.map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
        let reflectionsByEvent = Dictionary(reflections.map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
        let focusByEvent = Dictionary(grouping: focus, by: \.eventID)
        let videosByEvent = Dictionary(grouping: videos, by: \.eventID)
        let checklistByEvent = Dictionary(grouping: checklist, by: \.eventID)
        let setsBySession = Dictionary(grouping: wallballSets, by: \.sessionID)

        return ProfileSnapshot(
            profile: profile,
            programs: programs,
            sessions: sessions,
            combineResults: results.map { r in
                CombineBundle(result: r, measurements: (measurementsByResult[r.id] ?? []).sorted { metricOrder[$0.metric, default: 0] < metricOrder[$1.metric, default: 0] })
            },
            events: events.map { e in
                EventBundle(event: e, stats: statsByEvent[e.id], reflection: reflectionsByEvent[e.id],
                            focus: (focusByEvent[e.id] ?? []).sorted { $0.position < $1.position },
                            videos: (videosByEvent[e.id] ?? []).sorted { $0.position < $1.position },
                            checklist: (checklistByEvent[e.id] ?? []).sorted { $0.position < $1.position })
            },
            expenses: expenses,
            docs: docs,
            bodyMeasurements: bodyMeasurements,
            wallballDrills: wallballDrills,
            wallballSessions: wallballSessions.map { s in
                WallballBundle(session: s, sets: (setsBySession[s.id] ?? []).sorted { $0.position < $1.position })
            },
            seasonBudgets: seasonBudgets,
            programBudgets: programBudgets,
            trips: trips,
            lockedDocs: lockedDocs,
            access: access
        )
    }
}
