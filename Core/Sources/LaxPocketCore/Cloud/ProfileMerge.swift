import Foundation

/// What has to be written to the cloud for one table.
public struct TableChanges<Row: Hashable & Sendable, Key: Hashable & Sendable>: Hashable, Sendable {
    public var upserts: [Row] = []
    public var deletes: [Key] = []

    public init(upserts: [Row] = [], deletes: [Key] = []) {
        self.upserts = upserts
        self.deletes = deletes
    }

    public var isEmpty: Bool { upserts.isEmpty && deletes.isEmpty }
}

/// Everything one sync needs to write for a profile.
public struct SyncChanges: Hashable, Sendable {
    public var profileID: UUID
    /// Set when the profile row itself changed.
    public var profile: ProfileRow?
    public var programs = TableChanges<ProgramRow, String>()
    public var sessions = TableChanges<SessionRow, UUID>()
    public var combineResults = TableChanges<CombineBundle, UUID>()
    public var events = TableChanges<EventBundle, UUID>()
    public var expenses = TableChanges<ExpenseRow, UUID>()
    public var docs = TableChanges<MentalDocRow, UUID>()

    public init(profileID: UUID) {
        self.profileID = profileID
    }

    public var isEmpty: Bool {
        profile == nil && programs.isEmpty && sessions.isEmpty && combineResults.isEmpty && events.isEmpty && expenses.isEmpty && docs.isEmpty
    }
}

/// Three-way merge of a profile: what the cloud had at the last sync (base), what this device has now (local),
/// and what the cloud has now (remote).
///
/// Rules, per row:
/// - Changed on one side only → that side wins.
/// - Changed on both sides → this device wins.
/// - Deleted on one side, edited on the other → the edit wins, so nothing typed in is lost.
///
/// An event or a testing day merges as one unit with everything under it.
public enum ProfileMerge {
    public struct Outcome: Hashable, Sendable {
        /// What both sides hold once `changes` are written. Becomes the new local data and the new base.
        public var merged: ProfileSnapshot
        /// What to write to the cloud.
        public var changes: SyncChanges
    }

    /// Pass `remote: nil` when the profile isn't in the cloud (never uploaded, or removed there): everything local is uploaded.
    public static func merge(base: ProfileSnapshot?, local: ProfileSnapshot, remote: ProfileSnapshot?) -> Outcome {
        guard let remote else {
            var changes = SyncChanges(profileID: local.profile.id)
            changes.profile = local.profile
            changes.programs.upserts = local.programs
            changes.sessions.upserts = local.sessions
            changes.combineResults.upserts = local.combineResults
            changes.events.upserts = local.events
            changes.expenses.upserts = local.expenses
            changes.docs.upserts = local.docs
            return Outcome(merged: local, changes: changes)
        }

        var changes = SyncChanges(profileID: local.profile.id)
        let profile = rows(base: base.map { [$0.profile] } ?? [], local: [local.profile], remote: [remote.profile], key: \.id)
        // The profile row is never deleted by a sync, so there is always one.
        let mergedProfile = profile.merged.first ?? local.profile
        changes.profile = profile.upserts.first

        let programs = rows(base: base?.programs ?? [], local: local.programs, remote: remote.programs, key: \.id)
        changes.programs = TableChanges(upserts: programs.upserts, deletes: programs.deletes)
        let sessions = rows(base: base?.sessions ?? [], local: local.sessions, remote: remote.sessions, key: \.id)
        changes.sessions = TableChanges(upserts: sessions.upserts, deletes: sessions.deletes)
        let combine = rows(base: base?.combineResults ?? [], local: local.combineResults, remote: remote.combineResults, key: \.id)
        changes.combineResults = TableChanges(upserts: combine.upserts, deletes: combine.deletes)
        let events = rows(base: base?.events ?? [], local: local.events, remote: remote.events, key: \.id)
        changes.events = TableChanges(upserts: events.upserts, deletes: events.deletes)
        let expenses = rows(base: base?.expenses ?? [], local: local.expenses, remote: remote.expenses, key: \.id)
        changes.expenses = TableChanges(upserts: expenses.upserts, deletes: expenses.deletes)
        let docs = rows(base: base?.docs ?? [], local: local.docs, remote: remote.docs, key: \.id)
        changes.docs = TableChanges(upserts: docs.upserts, deletes: docs.deletes)

        let merged = ProfileSnapshot(profile: mergedProfile, programs: programs.merged, sessions: sessions.merged,
                                     combineResults: combine.merged, events: events.merged, expenses: expenses.merged, docs: docs.merged)
        return Outcome(merged: merged, changes: changes)
    }

    struct RowMerge<Row, Key> {
        var merged: [Row] = []
        var upserts: [Row] = []
        var deletes: [Key] = []
    }

    /// Merges one table. Output keeps local order, then rows only the cloud has.
    static func rows<Row: Equatable, Key: Hashable>(base: [Row], local: [Row], remote: [Row], key: (Row) -> Key) -> RowMerge<Row, Key> {
        func index(_ rows: [Row]) -> [Key: Row] {
            var result: [Key: Row] = [:]
            for row in rows { result[key(row)] = row }
            return result
        }
        let b = index(base), l = index(local), r = index(remote)

        var order: [Key] = []
        var seen = Set<Key>()
        for row in local + remote + base where seen.insert(key(row)).inserted {
            order.append(key(row))
        }

        var outcome = RowMerge<Row, Key>()
        for k in order {
            let before = b[k], mine = l[k], theirs = r[k]
            let result: Row?
            if mine == theirs {
                result = mine
            } else if mine == before {
                result = theirs                      // only the cloud changed it
            } else if let mine {
                result = mine                        // this device changed it (and wins a conflict)
                outcome.upserts.append(mine)
            } else if theirs == before {
                result = nil                         // deleted here, untouched in the cloud
                outcome.deletes.append(k)
            } else {
                result = theirs                      // deleted here but edited in the cloud: keep the edit
            }
            if let result { outcome.merged.append(result) }
        }
        return outcome
    }
}
