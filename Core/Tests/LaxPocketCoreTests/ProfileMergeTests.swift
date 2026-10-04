import XCTest
@testable import LaxPocketCore

final class ProfileMergeTests: XCTestCase {
    private let season = Fixtures.season()
    private var base: ProfileSnapshot { ProfileSnapshot(season) }

    func testNothingChanged() {
        let outcome = ProfileMerge.merge(base: base, local: base, remote: base)
        XCTAssertTrue(outcome.changes.isEmpty)
        XCTAssertEqual(outcome.merged, base)
    }

    func testFirstUploadSendsEverything() {
        let outcome = ProfileMerge.merge(base: nil, local: base, remote: nil)
        XCTAssertEqual(outcome.changes.profile, base.profile)
        XCTAssertEqual(outcome.changes.sessions.upserts.count, 3)
        XCTAssertEqual(outcome.changes.events.upserts.count, 2)
        XCTAssertEqual(outcome.changes.programs.upserts.count, 4)
        XCTAssertTrue(outcome.changes.sessions.deletes.isEmpty)
        XCTAssertEqual(outcome.merged, base)
    }

    /// A profile removed from the cloud is uploaded again rather than wiping this device.
    func testProfileMissingFromCloudIsReuploaded() {
        let outcome = ProfileMerge.merge(base: base, local: base, remote: nil)
        XCTAssertEqual(outcome.changes.sessions.upserts.count, 3)
        XCTAssertEqual(outcome.merged, base)
    }

    func testLocalChangesArePushed() {
        var local = season
        local.sessions[0].minutes = 120
        local.sessions.remove(at: 1)
        local.expenses.append(Expense(date: Fixtures.day(5), title: "Stick", category: .equipment, amount: 250))
        local.profile.firstName = "Samantha"

        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(outcome.changes.profile?.firstName, "Samantha")
        XCTAssertEqual(outcome.changes.sessions.upserts.map(\.minutes), [120])
        XCTAssertEqual(outcome.changes.sessions.deletes, [season.sessions[1].id])
        XCTAssertEqual(outcome.changes.expenses.upserts.map(\.title), ["Stick"])
        XCTAssertTrue(outcome.changes.events.isEmpty)
        XCTAssertEqual(outcome.merged, ProfileSnapshot(local))
    }

    func testRemoteChangesArePulled() {
        var remoteData = season
        remoteData.sessions[0].notes = "Edited on the other phone"
        remoteData.docs.removeAll()
        remoteData.events[0].stats?.goals = 3
        remoteData.programs.append(Program(id: "new", name: "New club", detail: "", group: .teams, sessionCategory: .team, monogram: "NC"))

        let outcome = ProfileMerge.merge(base: base, local: base, remote: ProfileSnapshot(remoteData))
        XCTAssertTrue(outcome.changes.isEmpty, "nothing to send")
        let merged = outcome.merged.appData
        XCTAssertEqual(merged.sessions.first { $0.id == season.sessions[0].id }?.notes, "Edited on the other phone")
        XCTAssertTrue(merged.docs.isEmpty)
        XCTAssertEqual(merged.events.first { $0.id == season.events[0].id }?.stats?.goals, 3)
        XCTAssertEqual(merged.programs.last?.id, "new")
    }

    func testBothSidesEditDifferentRows() {
        var local = season
        local.sessions[0].effort = 9
        var remote = season
        remote.sessions[1].effort = 4
        remote.expenses.append(Expense(date: Fixtures.day(6), title: "Hotel", category: .travel, amount: 180))

        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertEqual(outcome.changes.sessions.upserts.map(\.id), [season.sessions[0].id])
        XCTAssertTrue(outcome.changes.expenses.isEmpty)
        let merged = outcome.merged.appData
        XCTAssertEqual(merged.sessions.first { $0.id == season.sessions[0].id }?.effort, 9)
        XCTAssertEqual(merged.sessions.first { $0.id == season.sessions[1].id }?.effort, 4)
        XCTAssertTrue(merged.expenses.contains { $0.title == "Hotel" })
    }

    func testSameRowEditedOnBothSidesKeepsThisDevice() {
        var local = season
        local.sessions[0].notes = "Mine"
        var remote = season
        remote.sessions[0].notes = "Theirs"
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertEqual(outcome.changes.sessions.upserts.map(\.notes), ["Mine"])
        XCTAssertEqual(outcome.merged.sessions.first { $0.id == season.sessions[0].id }?.notes, "Mine")
    }

    func testEditBeatsDelete() {
        // Deleted here, edited in the cloud: the cloud's edit comes back.
        var local = season
        local.expenses.removeAll { $0.id == season.expenses[0].id }
        var remote = season
        remote.expenses[0].note = "Receipt attached"
        var outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertTrue(outcome.changes.expenses.isEmpty)
        XCTAssertEqual(outcome.merged.expenses.first { $0.id == season.expenses[0].id }?.note, "Receipt attached")

        // Deleted in the cloud, edited here: this device's edit is sent back up.
        local = season
        local.expenses[0].note = "Split with team"
        remote = season
        remote.expenses.remove(at: 0)
        outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertEqual(outcome.changes.expenses.upserts.map(\.note), ["Split with team"])
        XCTAssertTrue(outcome.changes.expenses.deletes.isEmpty)
    }

    func testDeleteOnOneSideOnly() {
        var remote = season
        remote.sessions.remove(at: 2)
        var outcome = ProfileMerge.merge(base: base, local: base, remote: ProfileSnapshot(remote))
        XCTAssertTrue(outcome.changes.isEmpty)
        XCTAssertEqual(outcome.merged.sessions.count, 2)

        var local = season
        local.events.removeAll()
        outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(Set(outcome.changes.events.deletes), Set(season.events.map(\.id)))
        XCTAssertTrue(outcome.merged.events.isEmpty)
    }

    func testHeightAndWeightMergeLikeOtherRows() {
        var local = season
        local.bodyMeasurements.append(BodyMeasurement(date: Fixtures.day(7), heightCm: 160.4))
        local.bodyMeasurements[0].note = "Morning"
        var remote = season
        remote.bodyMeasurements.remove(at: 2)
        remote.profile.bodyUnits = .imperial

        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertEqual(Set(outcome.changes.bodyMeasurements.upserts.map(\.id)), [local.bodyMeasurements[0].id, local.bodyMeasurements[3].id])
        XCTAssertTrue(outcome.changes.bodyMeasurements.deletes.isEmpty)
        XCTAssertNil(outcome.changes.profile, "the units change came from the cloud")
        let merged = outcome.merged.appData
        XCTAssertEqual(merged.bodyMeasurements.count, 3)
        XCTAssertFalse(merged.bodyMeasurements.contains { $0.id == season.bodyMeasurements[2].id })
        XCTAssertEqual(merged.bodyMeasurements.first?.note, "Morning")
        XCTAssertEqual(merged.profile.bodyUnits, .imperial)

        local = season
        local.bodyMeasurements.removeAll()
        let deleted = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(Set(deleted.changes.bodyMeasurements.deletes), Set(season.bodyMeasurements.map(\.id)))
    }

    func testWallballMergesLikeOtherRows() {
        var local = season
        local.wallballSessions[0].sets[1].reps = 45
        local.wallballDrills.append(WallballDrill(name: "Cross-body catch"))
        var remote = season
        remote.wallballSessions.remove(at: 1)
        remote.wallballDrills[0].defaultReps = 25

        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertEqual(outcome.changes.wallballSessions.upserts.map(\.id), [season.wallballSessions[0].id], "a changed set re-sends its session")
        XCTAssertEqual(outcome.changes.wallballSessions.upserts.first?.sets.count, 4)
        XCTAssertEqual(outcome.changes.wallballDrills.upserts.map(\.name), ["Cross-body catch"])
        let merged = outcome.merged.appData
        XCTAssertEqual(merged.wallballSessions.map(\.id), [season.wallballSessions[0].id])
        XCTAssertEqual(merged.wallballSessions[0].sets[1].reps, 45)
        XCTAssertEqual(merged.wallballDrills.first { $0.id == "twister" }?.defaultReps, 25)
        XCTAssertEqual(merged.wallballDrills.count, 3)

        local = season
        local.wallballSessions.removeAll()
        local.wallballDrills.removeAll { $0.id == "twister" }
        let deleted = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(Set(deleted.changes.wallballSessions.deletes), Set(season.wallballSessions.map(\.id)))
        XCTAssertEqual(deleted.changes.wallballDrills.deletes, ["twister"])
    }

    func testBudgetsMergeLikeOtherRows() {
        var local = season
        local.setProgramBudget(3500, programID: "club", season: 2026)
        local.setProgramBudget(0, programID: "skills-coach", season: 2026)
        var remote = season
        remote.setBudget(15_000, for: 2026)
        remote.setProgramBudget(400, programID: "gym", season: 2026)

        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertEqual(outcome.changes.programBudgets.upserts.map(\.amount), [3500])
        XCTAssertEqual(outcome.changes.programBudgets.deletes, [ProgramBudgetRow.Key(programID: "skills-coach", season: 2026)])
        XCTAssertTrue(outcome.changes.seasonBudgets.isEmpty)
        let merged = outcome.merged.appData
        XCTAssertEqual(merged.budget(for: 2026), 15_000)
        XCTAssertEqual(merged.programBudget("club", season: 2026), 3500)
        XCTAssertEqual(merged.programBudget("gym", season: 2026), 400)
        XCTAssertEqual(merged.programBudget("skills-coach", season: 2026), 0)

        local = season
        local.setBudget(0, for: 2026)
        let deleted = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(deleted.changes.seasonBudgets.deletes, [2026])
    }

    /// An event merges as one unit: editing a goal re-sends the whole event with its children.
    func testEventChildrenTravelWithTheEvent() {
        var local = season
        local.events[0].focus[1].outcome = .missed
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(outcome.changes.events.upserts.count, 1)
        XCTAssertEqual(outcome.changes.events.upserts.first?.focus.map(\.outcome), [.hit, .missed])
        XCTAssertEqual(outcome.changes.events.upserts.first?.videos.count, 1)
    }

    /// Without a base (e.g. first sync on a phone that already had data), nothing is deleted anywhere.
    func testNoBaseNeverDeletes() {
        var local = season
        local.sessions.removeLast()
        var remote = season
        remote.expenses.removeLast()
        let outcome = ProfileMerge.merge(base: nil, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))
        XCTAssertTrue(outcome.changes.sessions.deletes.isEmpty)
        XCTAssertTrue(outcome.changes.expenses.deletes.isEmpty)
        XCTAssertEqual(outcome.merged.sessions.count, 3)
        XCTAssertEqual(outcome.merged.expenses.count, 2)
        XCTAssertEqual(outcome.changes.expenses.upserts.map(\.id), [season.expenses[1].id])
    }

    /// Applying the pushed changes to the remote gives the merged result.
    func testMergedEqualsRemotePlusChanges() {
        var local = season
        local.sessions[0].minutes = 45
        local.docs.removeAll()
        var remote = season
        remote.sessions[2].notes = "cloud"
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: ProfileSnapshot(remote))

        var applied = ProfileSnapshot(remote)
        for row in outcome.changes.sessions.upserts {
            if let i = applied.sessions.firstIndex(where: { $0.id == row.id }) { applied.sessions[i] = row } else { applied.sessions.append(row) }
        }
        applied.docs.removeAll { outcome.changes.docs.deletes.contains($0.id) }
        XCTAssertEqual(Set(applied.sessions), Set(outcome.merged.sessions))
        XCTAssertEqual(Set(applied.docs), Set(outcome.merged.docs))
    }
}
