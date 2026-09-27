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

        return ProfileSnapshot.assemble(profile: profile, programs: programs, sessions: sessions, results: results, measurements: measurements,
                                        events: events, stats: stats, reflections: reflections, focus: focus, videos: videos,
                                        checklist: checklist, expenses: expenses, docs: docs)
    }

    /// Writes changes for one profile. Parents go before children and deletes go last, so foreign keys hold at every step.
    public func push(_ changes: SyncChanges) async throws {
        if let profile = changes.profile { try await client.upsert([profile]) }
        let byProfile = [URLQueryItem(name: "profile_id", value: "eq.\(changes.profileID.uuidString.lowercased())")]

        try await client.upsert(changes.programs.upserts)
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

        try await client.upsert(changes.expenses.upserts)
        try await client.upsert(changes.docs.upserts)

        func ids(_ keys: [UUID]) -> [String] { keys.map { $0.uuidString.lowercased() } }
        try await client.delete(SessionRow.table, where: "id", in: ids(changes.sessions.deletes), filters: byProfile)
        try await client.delete(CombineResultRow.table, where: "id", in: ids(changes.combineResults.deletes), filters: byProfile)
        try await client.delete(EventRow.table, where: "id", in: ids(changes.events.deletes), filters: byProfile)
        try await client.delete(ExpenseRow.table, where: "id", in: ids(changes.expenses.deletes), filters: byProfile)
        try await client.delete(MentalDocRow.table, where: "id", in: ids(changes.docs.deletes), filters: byProfile)
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

    /// Gives another LaxPocket account access to a profile. The other person has to have signed up already.
    public func share(profileID: UUID, email: String, role: ShareRole) async throws {
        _ = try await client.rpc("share_profile", params: [
            "p_profile_id": profileID.uuidString.lowercased(),
            "p_email": email,
            "p_role": role.rawValue
        ])
    }
}

extension ProfileSnapshot {
    /// Groups flat table rows back into a snapshot.
    static func assemble(profile: ProfileRow, programs: [ProgramRow], sessions: [SessionRow], results: [CombineResultRow],
                         measurements: [CombineMeasurementRow], events: [EventRow], stats: [GameStatsRow], reflections: [ReflectionRow],
                         focus: [FocusGoalRow], videos: [VideoRow], checklist: [ChecklistItemRow], expenses: [ExpenseRow],
                         docs: [MentalDocRow]) -> ProfileSnapshot {
        let metricOrder = Dictionary(uniqueKeysWithValues: CombineMetric.allCases.enumerated().map { ($1, $0) })
        let measurementsByResult = Dictionary(grouping: measurements, by: \.resultID)
        let statsByEvent = Dictionary(stats.map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
        let reflectionsByEvent = Dictionary(reflections.map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
        let focusByEvent = Dictionary(grouping: focus, by: \.eventID)
        let videosByEvent = Dictionary(grouping: videos, by: \.eventID)
        let checklistByEvent = Dictionary(grouping: checklist, by: \.eventID)

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
            docs: docs
        )
    }
}
