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
    public var bodyMeasurements = TableChanges<BodyMeasurementRow, UUID>()
    public var wallballDrills = TableChanges<WallballDrillRow, String>()
    public var wallballSessions = TableChanges<WallballBundle, UUID>()
    public var seasonBudgets = TableChanges<SeasonBudgetRow, Int>()
    public var programBudgets = TableChanges<ProgramBudgetRow, ProgramBudgetRow.Key>()
    public var trips = TableChanges<TripRow, UUID>()
    public var assignmentCompletions = TableChanges<CompletionRow, CompletionRow.Key>()

    public init(profileID: UUID) {
        self.profileID = profileID
    }

    public var isEmpty: Bool {
        profile == nil && programs.isEmpty && sessions.isEmpty && combineResults.isEmpty && events.isEmpty && expenses.isEmpty && docs.isEmpty
            && bodyMeasurements.isEmpty && wallballDrills.isEmpty && wallballSessions.isEmpty && seasonBudgets.isEmpty && programBudgets.isEmpty
            && trips.isEmpty && assignmentCompletions.isEmpty
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
/// An event, a testing day or a wall ball session merges as one unit with everything under it.
///
/// What the account can do with the athlete (`remote.access`) limits the merge: sections it can't read are dropped from
/// this device, sections it can only read take the cloud's copy, and nothing is written that the cloud would refuse.
public enum ProfileMerge {
    public struct Outcome: Hashable, Sendable {
        /// What both sides hold once `changes` are written. Becomes the new local data and the new base.
        public var merged: ProfileSnapshot
        /// What to write to the cloud.
        public var changes: SyncChanges
    }

    /// Pass `remote: nil` when the profile isn't in the cloud (never uploaded, or removed there): everything local is uploaded.
    public static func merge(base: ProfileSnapshot?, local: ProfileSnapshot, remote: ProfileSnapshot?) -> Outcome {
        guard var remote else {
            var changes = SyncChanges(profileID: local.profile.id)
            changes.profile = local.profile
            changes.programs.upserts = local.programs
            changes.sessions.upserts = local.sessions
            changes.combineResults.upserts = local.combineResults
            changes.events.upserts = local.events
            changes.expenses.upserts = local.expenses
            changes.docs.upserts = local.docs
            changes.bodyMeasurements.upserts = local.bodyMeasurements
            changes.wallballDrills.upserts = local.wallballDrills
            changes.wallballSessions.upserts = local.wallballSessions
            changes.seasonBudgets.upserts = local.seasonBudgets
            changes.programBudgets.upserts = local.programBudgets
            changes.trips.upserts = local.trips
            changes.assignmentCompletions.upserts = local.assignmentCompletions
            return Outcome(merged: local, changes: changes)
        }

        var base = base, local = local
        // A tick for a task the athlete no longer has (taken off the roster, or the coach removed it) can't be
        // written any more; leave it out on every side so it's neither sent nor deleted.
        let tasks = Set(remote.assignments.map(\.id))
        base?.assignmentCompletions.removeAll { !tasks.contains($0.assignmentID) }
        local.assignmentCompletions.removeAll { !tasks.contains($0.assignmentID) }
        remote.assignmentCompletions.removeAll { !tasks.contains($0.assignmentID) }
        if let access = remote.access {
            for section in ProfileSection.allCases where !access.canRead(section) {
                base = base?.replacing(section, from: nil)
                local = local.replacing(section, from: nil)
                remote = remote.replacing(section, from: nil)
            }
            for section in ProfileSection.allCases where access.canRead(section) && !access.canWrite(section) {
                local = local.replacing(section, from: remote)
            }
            if !access.canEditProfile { local.profile = remote.profile }
            if !access.canLockDocs { dropDocsClosedToThisAccount(base: base, local: &local, remote: remote) }
        }

        var outcome = mergeRows(base: base, local: local, remote: remote)
        if let access = remote.access {
            for section in ProfileSection.allCases where !access.canWrite(section) { outcome.changes.clear(section) }
            if !access.canEditProfile { outcome.changes.profile = nil }
        }
        outcome.merged.lockedDocs = remote.lockedDocs
        outcome.merged.access = remote.access
        outcome.merged.assignments = remote.assignments
        outcome.merged.coachNotes = remote.coachNotes
        return outcome
    }

    /// A doc the athlete locked or hid disappears from what this account can read. The cloud would refuse any change
    /// to it from here, so it leaves this device even if it was edited here: a doc that's now locked, or one that was
    /// here at the last sync and isn't in the cloud any more.
    static func dropDocsClosedToThisAccount(base: ProfileSnapshot?, local: inout ProfileSnapshot, remote: ProfileSnapshot) {
        let locked = Set(remote.lockedDocs.map(\.id))
        let inCloud = Set(remote.docs.map(\.id))
        let atLastSync = Set(base?.docs.map(\.id) ?? [])
        local.docs.removeAll { locked.contains($0.id) || (atLastSync.contains($0.id) && !inCloud.contains($0.id)) }
    }

    static func mergeRows(base: ProfileSnapshot?, local: ProfileSnapshot, remote: ProfileSnapshot) -> Outcome {
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
        let body = rows(base: base?.bodyMeasurements ?? [], local: local.bodyMeasurements, remote: remote.bodyMeasurements, key: \.id)
        changes.bodyMeasurements = TableChanges(upserts: body.upserts, deletes: body.deletes)
        let drills = rows(base: base?.wallballDrills ?? [], local: local.wallballDrills, remote: remote.wallballDrills, key: \.id)
        changes.wallballDrills = TableChanges(upserts: drills.upserts, deletes: drills.deletes)
        let wallball = rows(base: base?.wallballSessions ?? [], local: local.wallballSessions, remote: remote.wallballSessions, key: \.id)
        changes.wallballSessions = TableChanges(upserts: wallball.upserts, deletes: wallball.deletes)
        let seasonBudgets = rows(base: base?.seasonBudgets ?? [], local: local.seasonBudgets, remote: remote.seasonBudgets, key: \.season)
        changes.seasonBudgets = TableChanges(upserts: seasonBudgets.upserts, deletes: seasonBudgets.deletes)
        let programBudgets = rows(base: base?.programBudgets ?? [], local: local.programBudgets, remote: remote.programBudgets, key: \.key)
        changes.programBudgets = TableChanges(upserts: programBudgets.upserts, deletes: programBudgets.deletes)
        let trips = rows(base: base?.trips ?? [], local: local.trips, remote: remote.trips, key: \.id)
        changes.trips = TableChanges(upserts: trips.upserts, deletes: trips.deletes)
        let completions = rows(base: base?.assignmentCompletions ?? [], local: local.assignmentCompletions, remote: remote.assignmentCompletions,
                               key: \.key)
        changes.assignmentCompletions = TableChanges(upserts: completions.upserts, deletes: completions.deletes)

        var merged = ProfileSnapshot(profile: mergedProfile, programs: programs.merged, sessions: sessions.merged,
                                     combineResults: combine.merged, events: events.merged, expenses: expenses.merged, docs: docs.merged,
                                     bodyMeasurements: body.merged, wallballDrills: drills.merged, wallballSessions: wallball.merged,
                                     seasonBudgets: seasonBudgets.merged, programBudgets: programBudgets.merged, trips: trips.merged,
                                     assignmentCompletions: completions.merged)
        dropTripLinksToDeletedRows(&merged, &changes)
        return Outcome(merged: merged, changes: changes)
    }

    /// A trip or expense edited here while what it points at was deleted on another device would fail its foreign key
    /// and stop every sync after it. The link is cleared instead, in the merged data and in what's written.
    static func dropTripLinksToDeletedRows(_ merged: inout ProfileSnapshot, _ changes: inout SyncChanges) {
        let programIDs = Set(merged.programs.map(\.id))
        let eventIDs = Set(merged.events.map(\.id))
        let tripIDs = Set(merged.trips.map(\.id))
        for index in merged.trips.indices {
            var trip = merged.trips[index]
            if let id = trip.programID, !programIDs.contains(id) { trip.programID = nil }
            if let id = trip.eventID, !eventIDs.contains(id) { trip.eventID = nil }
            guard trip != merged.trips[index] else { continue }
            merged.trips[index] = trip
            changes.trips.upserts.removeAll { $0.id == trip.id }
            changes.trips.upserts.append(trip)
        }
        for index in merged.expenses.indices {
            guard let id = merged.expenses[index].tripID, !tripIDs.contains(id) else { continue }
            merged.expenses[index].tripID = nil
            changes.expenses.upserts.removeAll { $0.id == merged.expenses[index].id }
            changes.expenses.upserts.append(merged.expenses[index])
        }
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

extension ProfileSnapshot {
    /// The same snapshot with one section's rows taken from `other`, or emptied when `other` is nil.
    func replacing(_ section: ProfileSection, from other: ProfileSnapshot?) -> ProfileSnapshot {
        var copy = self
        switch section {
        case .training:
            copy.programs = other?.programs ?? []
            copy.sessions = other?.sessions ?? []
            copy.combineResults = other?.combineResults ?? []
            copy.wallballDrills = other?.wallballDrills ?? []
            copy.wallballSessions = other?.wallballSessions ?? []
            copy.assignmentCompletions = other?.assignmentCompletions ?? []
        case .events:
            copy.events = other?.events ?? []
        case .health:
            copy.bodyMeasurements = other?.bodyMeasurements ?? []
        case .budget:
            copy.expenses = other?.expenses ?? []
            copy.trips = other?.trips ?? []
            copy.seasonBudgets = other?.seasonBudgets ?? []
            copy.programBudgets = other?.programBudgets ?? []
        case .mental:
            copy.docs = other?.docs ?? []
            copy.lockedDocs = other?.lockedDocs ?? []
        }
        return copy
    }
}

extension SyncChanges {
    /// Writes nothing for a section.
    mutating func clear(_ section: ProfileSection) {
        switch section {
        case .training:
            programs = .init()
            sessions = .init()
            combineResults = .init()
            wallballDrills = .init()
            wallballSessions = .init()
            assignmentCompletions = .init()
        case .events:
            events = .init()
        case .health:
            bodyMeasurements = .init()
        case .budget:
            expenses = .init()
            trips = .init()
            seasonBudgets = .init()
            programBudgets = .init()
        case .mental:
            docs = .init()
        }
    }
}
