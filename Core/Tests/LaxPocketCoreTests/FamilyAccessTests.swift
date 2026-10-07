import XCTest
@testable import LaxPocketCore

final class FamilyAccessTests: XCTestCase {
    private let season = Fixtures.season()
    private var base: ProfileSnapshot { ProfileSnapshot(season) }

    private static let owner = ProfileAccess(role: .owner, relationships: [.parent])
    private static let parent = ProfileAccess(role: .editor, relationships: [.parent])
    private static let athlete = ProfileAccess(role: .editor, relationships: [.athlete])
    private static let coach = ProfileAccess(role: .viewer, relationships: [.coach])

    /// The cloud's copy of the fixture season as an account with `access` reads it.
    private func cloud(_ data: AppData? = nil, as access: ProfileAccess, lockedDocs: [LockedMentalDocRow] = []) -> ProfileSnapshot {
        var snapshot = ProfileSnapshot(data ?? season)
        for section in ProfileSection.allCases where !access.canRead(section) { snapshot = snapshot.replacing(section, from: nil) }
        snapshot.lockedDocs = lockedDocs
        snapshot.access = access
        return snapshot
    }

    // MARK: - Sections

    /// Same table as private.readable_sections / private.writable_sections in the family accounts migration.
    func testSectionsByRelationship() {
        let all = Set(ProfileSection.allCases)
        XCTAssertEqual(Relationship.parent.readableSections, all)
        XCTAssertEqual(Relationship.parent.writableSections, all)
        XCTAssertEqual(Relationship.athlete.readableSections, all)
        XCTAssertEqual(Relationship.athlete.writableSections, [.training, .events, .health, .mental])
        XCTAssertEqual(Relationship.coach.readableSections, [.training, .events])
        XCTAssertEqual(Relationship.mentalCoach.readableSections, [.training, .events, .mental])
        XCTAssertTrue(Relationship.coach.writableSections.isEmpty)
        XCTAssertTrue(Relationship.mentalCoach.writableSections.isEmpty)
    }

    func testAccessCombinesRoleAndRelationships() {
        XCTAssertTrue(Self.athlete.canRead(.budget))
        XCTAssertFalse(Self.athlete.canWrite(.budget))
        XCTAssertTrue(Self.athlete.canWrite(.health))
        XCTAssertTrue(Self.athlete.canLockDocs)
        XCTAssertFalse(Self.parent.canLockDocs)
        XCTAssertFalse(Self.parent.canManagePeople)

        let athleteOwner = ProfileAccess(role: .owner, relationships: [.athlete])
        XCTAssertTrue(athleteOwner.canWrite(.budget), "the owner changes everything")
        XCTAssertTrue(athleteOwner.canManagePeople)

        let readOnlyParent = ProfileAccess(role: .viewer, relationships: [.parent])
        XCTAssertTrue(readOnlyParent.canRead(.budget))
        XCTAssertFalse(readOnlyParent.canWrite(.training))
        XCTAssertFalse(readOnlyParent.canEditProfile)

        let both = ProfileAccess(role: .viewer, relationships: [.coach, .mentalCoach])
        XCTAssertTrue(both.canRead(.mental))
        XCTAssertFalse(both.canRead(.health))
        XCTAssertEqual(both.summary, "Coach, Mental coach")
        XCTAssertEqual(Self.owner.summary, "Parent · Owner")
    }

    func testAthletesNotInTheCloudShowEverything() {
        XCTAssertNil(season.access)
        XCTAssertTrue(ProfileSection.allCases.allSatisfy { season.canRead($0) && season.canWrite($0) })
        var coached = season
        coached.access = Self.coach
        XCTAssertFalse(coached.canRead(.budget))
        XCTAssertFalse(coached.canWrite(.training))
    }

    // MARK: - Rows

    func testReadsDocsAndFilesFromBeforeLocking() throws {
        let row = #"{"id":"60000000-0000-4000-8000-000000000001","profile_id":"10000000-0000-4000-8000-000000000001","title":"Routine","#
            + #""url":"https://example.com/d","folder":"routines","kind":"link","status":"new","doc_updated_at":"2026-09-22T12:00:00Z","#
            + #""doc_updated_by":"","note":""}"#
        XCTAssertEqual(try JSONDecoder().decode(MentalDocRow.self, from: Data(row.utf8)).visibility, .shared)

        var json = try JSONSerialization.jsonObject(with: AppData.encoder.encode(season)) as! [String: Any]
        json["lockedDocs"] = nil
        json["access"] = nil
        var docs = json["docs"] as! [[String: Any]]
        docs[0]["visibility"] = nil
        json["docs"] = docs
        let old = try AppData.decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.docs[0].visibility, .shared)
        XCTAssertTrue(old.lockedDocs.isEmpty)
        XCTAssertNil(old.access)
    }

    func testSnapshotKeepsLockedDocsAndAccess() {
        var data = season
        data.docs[0].visibility = .hidden
        data.lockedDocs = [LockedMentalDoc(id: UUID(), folder: .journal, updatedAt: Fixtures.day(3))]
        data.access = Self.athlete
        let snapshot = ProfileSnapshot(data)
        XCTAssertEqual(snapshot.docs[0].visibility, .hidden)
        XCTAssertEqual(snapshot.appData, data)
        XCTAssertFalse(snapshot.hasSameRows(as: ProfileSnapshot(season)), "a new placeholder or access is a change to show")
    }

    func testMemberRowsSkipRelationshipsTheAppDoesntKnow() throws {
        let row = #"{"profile_id":"10000000-0000-4000-8000-000000000001","role":"viewer","relationships":["coach","physio"]}"#
        let member = try SupabaseClient.decoder.decode(MemberRow.self, from: Data(row.utf8))
        XCTAssertNil(member.userID)
        XCTAssertEqual(member.access, ProfileAccess(role: .viewer, relationships: [.coach]))
    }

    func testInvites() throws {
        let row = #"{"code":"ABCD2345","profile_id":"10000000-0000-4000-8000-000000000001","relationship":"athlete","#
            + #""created_at":"2026-10-01T12:00:00+00:00","expires_at":"2026-10-08T12:00:00+00:00","accepted_at":null}"#
        let invite = try SupabaseClient.decoder.decode(InviteRow.self, from: Data(row.utf8))
        XCTAssertEqual(invite.displayCode, "ABCD-2345")
        XCTAssertEqual(invite.relationship, .athlete)
        XCTAssertTrue(invite.isOpen(now: invite.createdAt.date))
        XCTAssertFalse(invite.isOpen(now: invite.expiresAt.date.addingTimeInterval(1)))
    }

    func testAccountRowsEncodeTheirColumns() throws {
        let row = AccountRow(userID: UUID(), displayName: "Sam", kind: .mentalCoach)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as! [String: Any]
        XCTAssertEqual(Set(json.keys), Set(AccountRow.columns))
        XCTAssertEqual(json["kind"] as? String, "mentalCoach")
    }

    func testPeopleNames() {
        let id = UUID()
        XCTAssertEqual(ProfilePerson(userID: id, name: " ", access: Self.coach, isMe: false).displayName, "SportsPocket account")
        XCTAssertEqual(ProfilePerson(userID: id, name: "Sam", access: Self.athlete, isMe: true).displayName, "Sam (you)")
    }

    // MARK: - Merging what an account can see

    func testCoachKeepsOnlyWhatTheyCanSee() {
        var local = season
        local.expenses[0].amount = 1
        local.sessions[0].minutes = 5
        let remote = cloud(as: Self.coach)
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: remote)
        XCTAssertTrue(outcome.changes.isEmpty, "a viewer writes nothing")
        let merged = outcome.merged.appData
        XCTAssertTrue(merged.expenses.isEmpty && merged.trips.isEmpty && merged.seasonBudgets.isEmpty && merged.programBudgets.isEmpty)
        XCTAssertTrue(merged.bodyMeasurements.isEmpty)
        XCTAssertTrue(merged.docs.isEmpty)
        XCTAssertEqual(merged.sessions[0].minutes, 90, "the edit is replaced by the cloud's copy")
        XCTAssertEqual(merged.events.count, 2)
        XCTAssertEqual(merged.access, Self.coach)
    }

    func testAthleteChangesTrainingButNotTheBudget() {
        var local = season
        local.sessions[0].minutes = 120
        local.expenses[0].amount = 1
        local.setBudget(99, for: 2026)
        local.profile.weeklyGoalHours = 15
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: cloud(as: Self.athlete))
        XCTAssertEqual(outcome.changes.sessions.upserts.map(\.minutes), [120])
        XCTAssertEqual(outcome.changes.profile?.weeklyGoalHours, 15)
        XCTAssertTrue(outcome.changes.expenses.isEmpty)
        XCTAssertTrue(outcome.changes.seasonBudgets.isEmpty)
        let merged = outcome.merged.appData
        XCTAssertEqual(merged.expenses[0].amount, 1850)
        XCTAssertEqual(merged.budget(for: 2026), 14_000)
    }

    /// Deleting an event clears its trip's link. The database does that itself, so an athlete doesn't send the trip.
    func testAthleteDeletingAnEventDoesntWriteTheTrip() {
        var local = season
        local.events.removeAll { $0.id == season.events[1].id }
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: cloud(as: Self.athlete))
        XCTAssertEqual(outcome.changes.events.deletes, [season.events[1].id])
        XCTAssertTrue(outcome.changes.trips.isEmpty)

        let asOwner = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: cloud(as: Self.owner))
        XCTAssertEqual(asOwner.changes.trips.upserts.map(\.eventID), [nil])
    }

    func testParentLosesADocTheAthleteLocked() {
        let doc = season.docs[0]
        var local = season
        local.docs[0].status = .reviewed
        var remoteData = season
        remoteData.docs = []
        let placeholder = LockedMentalDocRow(id: doc.id, profileID: season.id, folder: doc.folder, docUpdatedAt: Timestamp(doc.updatedAt))
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: cloud(remoteData, as: Self.owner, lockedDocs: [placeholder]))
        XCTAssertTrue(outcome.changes.docs.isEmpty, "the cloud would refuse the edit")
        XCTAssertTrue(outcome.merged.appData.docs.isEmpty)
        XCTAssertEqual(outcome.merged.appData.lockedDocs.map(\.id), [doc.id])

        // Without a sync record (say, the first sync after signing in), the placeholder alone is enough.
        let first = ProfileMerge.merge(base: nil, local: ProfileSnapshot(local), remote: cloud(remoteData, as: Self.owner, lockedDocs: [placeholder]))
        XCTAssertTrue(first.changes.docs.isEmpty)
    }

    func testParentLosesADocTheAthleteHid() {
        var local = season
        local.docs[0].note = "Edited here"
        var remoteData = season
        remoteData.docs = []
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: cloud(remoteData, as: Self.parent))
        XCTAssertTrue(outcome.changes.docs.isEmpty)
        XCTAssertTrue(outcome.merged.docs.isEmpty)
    }

    func testAthleteKeepsAnEditedDocDeletedElsewhere() {
        var local = season
        local.docs[0].visibility = .locked
        var remoteData = season
        remoteData.docs = []
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: cloud(remoteData, as: Self.athlete))
        XCTAssertEqual(outcome.changes.docs.upserts.map(\.visibility), [.locked], "the usual rule: the edit wins")
    }
}
