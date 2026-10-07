import XCTest
@testable import LaxPocketCore

/// Syncs through a real PostgREST serving the schema in supabase/migrations.
///
/// Skipped unless these are set (CI's "Supabase schema & sync" job sets them up):
///   LAXPOCKET_E2E_REST_URL   e.g. http://127.0.0.1:3000
///   LAXPOCKET_E2E_TOKEN_A    JWT for account A (role "authenticated")
///   LAXPOCKET_E2E_TOKEN_B    JWT for account B
///   LAXPOCKET_E2E_EMAIL_B    account B's email in auth.users
final class CloudSyncIntegrationTests: XCTestCase {
    private var restURL: URL!
    private var tokenA = ""
    private var tokenB = ""
    private var emailB = ""

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["LAXPOCKET_E2E_REST_URL"].flatMap(URL.init(string:)),
              let a = env["LAXPOCKET_E2E_TOKEN_A"], let b = env["LAXPOCKET_E2E_TOKEN_B"], let email = env["LAXPOCKET_E2E_EMAIL_B"] else {
            // CI sets LAXPOCKET_E2E_REQUIRED so a broken setup fails instead of quietly skipping.
            if env["LAXPOCKET_E2E_REQUIRED"] != nil { XCTFail("LAXPOCKET_E2E_* variables are missing") }
            throw XCTSkip("Set LAXPOCKET_E2E_* to run against PostgREST")
        }
        restURL = url
        tokenA = a
        tokenB = b
        emailB = email
    }

    private func sync(_ token: String, pageSize: Int = 1000) async -> CloudSync {
        let config = SupabaseConfig(url: restURL, anonKey: "anon", restURL: restURL)
        let session = AuthSession(accessToken: token, refreshToken: "unused", expiresAt: .distantFuture, userID: UUID(), email: nil)
        let client = SupabaseClient(config: config, session: session)
        await client.setPageSize(pageSize)
        return CloudSync(client: client)
    }

    /// Order-independent comparison of what two sides hold.
    private func assertSame(_ a: ProfileSnapshot?, _ b: ProfileSnapshot?, file: StaticString = #filePath, line: UInt = #line) {
        guard let a, let b else { return XCTFail("missing snapshot", file: file, line: line) }
        XCTAssertEqual(a.profile, b.profile, file: file, line: line)
        XCTAssertEqual(Set(a.programs), Set(b.programs), "programs", file: file, line: line)
        XCTAssertEqual(Set(a.sessions), Set(b.sessions), "sessions", file: file, line: line)
        XCTAssertEqual(Set(a.combineResults), Set(b.combineResults), "combine", file: file, line: line)
        XCTAssertEqual(Set(a.events), Set(b.events), "events", file: file, line: line)
        XCTAssertEqual(Set(a.expenses), Set(b.expenses), "expenses", file: file, line: line)
        XCTAssertEqual(Set(a.docs), Set(b.docs), "docs", file: file, line: line)
        XCTAssertEqual(Set(a.bodyMeasurements), Set(b.bodyMeasurements), "height and weight", file: file, line: line)
        XCTAssertEqual(Set(a.wallballDrills), Set(b.wallballDrills), "wall ball drills", file: file, line: line)
        XCTAssertEqual(Set(a.wallballSessions), Set(b.wallballSessions), "wall ball", file: file, line: line)
        XCTAssertEqual(Set(a.seasonBudgets), Set(b.seasonBudgets), "season budgets", file: file, line: line)
        XCTAssertEqual(Set(a.programBudgets), Set(b.programBudgets), "program budgets", file: file, line: line)
        XCTAssertEqual(Set(a.trips), Set(b.trips), "trips", file: file, line: line)
    }

    func testTwoDevicesSyncOneAthlete() async throws {
        let season = Fixtures.season(name: "E2E \(UUID().uuidString.prefix(6))")
        // A small page size makes every read span several pages.
        let phone = await sync(tokenA, pageSize: 2)
        let tablet = await sync(tokenA)

        // 1. First upload from the phone.
        var phoneBase = try await phone.sync(local: season, base: nil)
        assertSame(phoneBase, ProfileSnapshot(season))
        let uploaded = try await phone.snapshot(profileID: season.id)
        assertSame(uploaded, ProfileSnapshot(season))
        let visible = try await phone.profiles()
        XCTAssertTrue(visible.contains { $0.id == season.id })

        // 2. The tablet downloads it.
        let downloaded = try await tablet.snapshot(profileID: season.id)
        var tabletBase = try XCTUnwrap(downloaded)
        var tabletData = tabletBase.appData
        assertSame(ProfileSnapshot(tabletData), ProfileSnapshot(season))

        // 3. Both edit, then sync one after the other.
        var phoneData = phoneBase.appData
        phoneData.sessions[0].minutes = 75
        phoneData.expenses.removeAll { $0.title.hasPrefix("Skills coach") }
        phoneData.programs.removeAll { $0.id == "combine" }
        phoneData.events[0].focus[1].outcome = .missed
        phoneData.events[0].stats = nil
        phoneData.events[0].videos = []
        phoneData.combineResults[0].measurements.removeAll { $0.metric == .gripLeft }
        phoneData.events.append(SeasonEvent(kind: .tournament, title: "Winter tournament", team: "Club 2031", date: Fixtures.day(90), endDate: Fixtures.day(91)))
        phoneData.bodyMeasurements[1].heightCm = 160.1
        phoneData.bodyMeasurements.removeAll { $0.id == season.bodyMeasurements[2].id }
        phoneData.wallballSessions[0].sets.removeAll { $0.drillID == "twister" }
        phoneData.wallballSessions[0].sets[0].reps = 60
        phoneData.wallballDrills.removeAll { $0.id == "behind-the-back" }
        phoneData.setProgramBudget(3500, programID: "club", season: 2026)
        phoneData.programs[0].lastSeason = 2029
        phoneData.expenses[0].note = "Paid by e-transfer"
        phoneData.trips[0].hotelName = "Lakeside Hotel"
        phoneData.trips[0].hotelCheckOut = Fixtures.day(61, hour: 11)
        let springTrip = Trip(name: "Spring tournament", destination: "Baltimore, MD", departureDate: Fixtures.day(200), returnDate: Fixtures.day(202),
                              travelMode: .fly, travelDetails: "AC 123")
        phoneData.trips.append(springTrip)

        tabletData.sessions[2].notes = "From the tablet"
        tabletData.docs.append(MentalDoc(title: "Season goals", url: URL(string: "https://docs.google.com/document/d/xyz")!, folder: .goals,
                                         updatedAt: Fixtures.day(2), updatedBy: "Sam"))
        tabletData.profile.weeklyGoalHours = 14
        tabletData.profile.bodyUnits = .imperial
        tabletData.bodyMeasurements.append(BodyMeasurement(date: Fixtures.day(5, hour: 8), heightCm: 160.3, weightKg: 48.53))
        tabletData.wallballSessions.append(WallballSession(date: Fixtures.day(2, hour: 7), sets: [WallballSet(drillID: "sidearm", hand: .left, reps: 25)]))
        tabletData.wallballSessions.removeAll { $0.id == season.wallballSessions[1].id }
        tabletData.setBudget(15_000, for: 2026)
        tabletData.setProgramBudget(0, programID: "skills-coach", season: 2026)
        tabletData.expenses.append(Expense(date: Fixtures.day(6), title: "Club jacket", category: .equipment, amount: 95, programID: "club", season: 2027))
        tabletData.expenses.append(Expense(date: Fixtures.day(60), title: "Team dinner", category: .food, amount: 64.25,
                                           tripID: season.trips[0].id))
        var hotel = Expense(date: Fixtures.day(61), title: "Hotel", category: .lodging, amount: 0, tripID: season.trips[0].id)
        hotel.setPaid(410.5, in: .usd, rate: 1.3725)
        tabletData.expenses.append(hotel)
        tabletData.profile.usdToCAD = 1.3725
        tabletData.profile.benchmarkGroup = nil

        phoneBase = try await phone.sync(local: phoneData, base: phoneBase)
        tabletBase = try await tablet.sync(local: tabletData, base: tabletBase)
        phoneBase = try await phone.sync(local: phoneBase.appData, base: phoneBase)

        // 4. Both now hold both sets of edits, and so does the cloud.
        assertSame(phoneBase, tabletBase)
        let cloudNow = try await phone.snapshot(profileID: season.id)
        let cloud = try XCTUnwrap(cloudNow)
        assertSame(cloud, phoneBase)
        let final = cloud.appData
        XCTAssertEqual(final.sessions.first { $0.id == season.sessions[0].id }?.minutes, 75)
        XCTAssertEqual(final.sessions.first { $0.id == season.sessions[2].id }?.notes, "From the tablet")
        XCTAssertEqual(final.expenses.count, 4)
        let usHotel = try XCTUnwrap(final.expenses.first { $0.currency == .usd })
        XCTAssertEqual(usHotel.paidAmount, 410.5)
        XCTAssertEqual(usHotel.amount, 563.41)
        XCTAssertEqual(final.profile.usdToCAD, 1.3725)
        XCTAssertNil(final.profile.benchmarkGroup, "taking the athlete off NDTP clears the group in the cloud")
        XCTAssertEqual(final.expenses.first { $0.programID == "club" && $0.season == 2026 }?.note, "Paid by e-transfer")
        XCTAssertEqual(final.expenses.first { $0.category == .food }?.tripID, season.trips[0].id)
        XCTAssertEqual(final.trips.map(\.name), ["Fall showcase", "Spring tournament"])
        XCTAssertEqual(final.trips[0].hotelName, "Lakeside Hotel")
        XCTAssertEqual(final.trips[0].eventID, season.events[1].id)
        XCTAssertEqual(final.trips[1].travelMode, .fly)
        XCTAssertEqual(TripMath.summary(final.trips[0], in: final).spent, 64.25 + 563.41)
        XCTAssertEqual(final.expenses.first { $0.season == 2027 }?.title, "Club jacket")
        XCTAssertEqual(final.budget(for: 2026), 15_000)
        XCTAssertEqual(final.programBudgets.map(\.amount), [3500, 3200])
        XCTAssertEqual(final.programs.first { $0.id == "club" }?.lastSeason, 2029)
        XCTAssertFalse(final.programs.contains { $0.id == "combine" })
        XCTAssertEqual(final.docs.count, 2)
        XCTAssertEqual(final.profile.weeklyGoalHours, 14)
        XCTAssertEqual(final.profile.bodyUnits, .imperial)
        XCTAssertEqual(final.bodyMeasurements.map(\.heightCm), [157.5, 160.1, 160.3])
        XCTAssertEqual(final.bodyMeasurements.last?.weightKg, 48.53)
        XCTAssertTrue(final.events.contains { $0.title == "Winter tournament" })
        XCTAssertEqual(final.wallballSessions.map(\.reps.total), [130, 25])
        XCTAssertEqual(final.wallballSessions[0].sets.map(\.drillID), ["overhand", "overhand", "switch-hands"])
        XCTAssertEqual(final.wallballDrills.map(\.id), ["twister"])
        let game = try XCTUnwrap(final.events.first { $0.id == season.events[0].id })
        XCTAssertNil(game.stats)
        XCTAssertTrue(game.videos.isEmpty)
        XCTAssertEqual(game.focus.map(\.outcome), [.hit, .missed])
        XCTAssertNotNil(game.reflection)
        XCTAssertNil(final.combineResults[0].value(for: .gripLeft))
        XCTAssertEqual(final.combineResults[0].value(for: .gripRight), 285)

        // 5. Nothing left to send.
        let again = ProfileMerge.merge(base: phoneBase, local: ProfileSnapshot(final), remote: cloud)
        XCTAssertTrue(again.changes.isEmpty)

        // 6. Another account can't see it until it's shared, and a viewer's changes don't reach the cloud.
        let other = await sync(tokenB)
        let hidden = try await other.snapshot(profileID: season.id)
        XCTAssertNil(hidden)
        try await phone.share(profileID: season.id, email: emailB, role: .viewer)
        let shared = try await other.snapshot(profileID: season.id)
        assertSame(shared, cloud)
        XCTAssertEqual(shared?.access, ProfileAccess(role: .viewer, relationships: [.parent]))
        var viewerEdit = final
        viewerEdit.sessions[0].minutes = 5
        let viewerSynced = try await other.sync(local: viewerEdit, base: shared)
        XCTAssertEqual(viewerSynced.appData.sessions.first { $0.id == season.sessions[0].id }?.minutes, 75, "the cloud's copy wins")
        let afterViewer = try await phone.snapshot(profileID: season.id)
        assertSame(afterViewer, cloud)
        do {
            try await other.push({ var c = SyncChanges(profileID: season.id); c.sessions.upserts = ProfileSnapshot(viewerEdit).sessions; return c }())
            XCTFail("a viewer can't write")
        } catch {
            XCTAssertEqual(error.localizedDescription, "This account can’t change that athlete (view-only access).")
        }
        do {
            try await other.deleteProfile(season.id)
            XCTFail("only the owner can delete")
        } catch {}

        // 7. The owner deletes it from the cloud.
        try await phone.deleteProfile(season.id)
        let gone = try await phone.snapshot(profileID: season.id)
        XCTAssertNil(gone)
    }

    /// The account a test token signs in as (the JWT's subject).
    private func userID(_ token: String) throws -> UUID {
        var payload = String(token.split(separator: ".")[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        let claims = try JSONSerialization.jsonObject(with: XCTUnwrap(Data(base64Encoded: payload))) as? [String: Any]
        return try XCTUnwrap((claims?["sub"] as? String).flatMap(UUID.init(uuidString:)))
    }

    func testCoachRosterSeesTrainingAndEventsOnly() async throws {
        let season = Fixtures.season(name: "E2E coached \(UUID().uuidString.prefix(6))")
        let parent = await sync(tokenA)
        let coach = await sync(tokenB)
        let now = Fixtures.day(3, hour: 20)
        _ = try await parent.sync(local: season, base: nil)

        // 1. The coach makes a roster; the parent checks the code, then adds the athlete.
        try await coach.saveAccount(AccountRow(userID: try userID(tokenB), displayName: "Coach B", kind: .coach))
        let rosterID = try await coach.createRoster(name: "E2E U15", kind: .team)
        let made = try await coach.rosters()
        let code = try XCTUnwrap(made.first { $0.id == rosterID }?.joinCode)
        let info = try await parent.describeCode(code.lowercased())
        XCTAssertEqual(info, .roster(name: "E2E U15", kind: .team, coachName: "Coach B"))
        let joined = try await parent.joinRoster(code: code, profileID: season.id)
        XCTAssertEqual(joined, rosterID)
        let coaches = try await parent.athleteCoaches(profileID: season.id)
        XCTAssertEqual(coaches.map(\.rosterID), [rosterID])
        XCTAssertEqual(coaches.first?.displayName, "Coach B")
        XCTAssertEqual(coaches.first?.canOpenLocked, false)

        // 2. The coach reads training and events, and nothing else.
        let rosters = try await coach.coachWorkspace(now: now)
        let athlete = try XCTUnwrap(rosters.first { $0.id == rosterID }?.athletes.first)
        XCTAssertEqual(athlete.data.profile.firstName, season.profile.firstName)
        XCTAssertEqual(Set(athlete.data.sessions.map(\.id)), Set(season.sessions.map(\.id)))
        XCTAssertEqual(athlete.data.wallballSessions.map(\.reps.total).sorted(), season.wallballSessions.map(\.reps.total).sorted())
        XCTAssertEqual(athlete.data.events.count, 2)
        XCTAssertEqual(athlete.data.events.first { $0.id == season.events[0].id }?.focus.count, 2)
        XCTAssertTrue(athlete.data.expenses.isEmpty && athlete.data.trips.isEmpty && athlete.data.bodyMeasurements.isEmpty)
        XCTAssertTrue(athlete.data.docs.isEmpty && athlete.data.lockedDocs.isEmpty)
        XCTAssertEqual(athlete.week(now: now).lastResult?.title, "vs Rivals")

        // 3. A new code stops the old one; the roster can close; the parent takes the athlete off.
        let fresh = try await coach.resetRosterCode(rosterID, open: true)
        XCTAssertNotEqual(fresh, code)
        let closed = try await coach.resetRosterCode(rosterID, open: false)
        XCTAssertNil(closed)
        do {
            _ = try await parent.describeCode(code)
            XCTFail("the old code stopped working")
        } catch {}
        try await parent.removeFromRoster(rosterID: rosterID, profileID: season.id)
        let after = try await coach.coachWorkspace(now: now)
        XCTAssertEqual(after.first { $0.id == rosterID }?.athletes.count, 0)

        try await coach.deleteRoster(rosterID)
        try await parent.deleteProfile(season.id)
    }

    func testCoachTaskIsSeenAndTickedOff() async throws {
        let season = Fixtures.season(name: "E2E tasks \(UUID().uuidString.prefix(6))")
        let parent = await sync(tokenA)
        let coach = await sync(tokenB)
        let now = Date()
        let calendar = Calendar.laxWeek
        _ = try await parent.sync(local: season, base: nil)
        try await coach.saveAccount(AccountRow(userID: try userID(tokenB), displayName: "Coach B", kind: .coach))
        let rosterID = try await coach.createRoster(name: "E2E tasks", kind: .team)
        let made = try await coach.rosters()
        let code = try XCTUnwrap(made.first { $0.id == rosterID }?.joinCode)
        _ = try await parent.joinRoster(code: code, profileID: season.id)

        // 1. The coach gives the roster a one-off task and the athlete a daily one, and writes a note on a game.
        let film = Assignment(rosterID: rosterID, kind: .check, title: "Watch the Rivals film", schedule: .once, startsOn: DayKey(now, calendar: calendar),
                              dueOn: DayKey(now.addingTimeInterval(3 * 86_400), calendar: calendar))
        let reps = Assignment(rosterID: rosterID, profileID: season.id, kind: .wallball, title: "Reps", schedule: .daily,
                              startsOn: DayKey(now, calendar: calendar), targetReps: 100)
        try await coach.saveAssignment(film)
        try await coach.saveAssignment(reps)
        try await coach.saveCoachNote(eventID: season.events[0].id, profileID: season.id, note: "Great draws")

        // 2. The family sees both tasks and the note, with the coach's name, and ticks the film off.
        let downloaded = try await parent.snapshot(profileID: season.id)
        var base = try XCTUnwrap(downloaded)
        var data = base.appData
        XCTAssertEqual(Set(data.assignments.map(\.id)), [film.id, reps.id])
        XCTAssertTrue(data.assignments.allSatisfy { $0.coachName == "Coach B" && $0.rosterName == "E2E tasks" })
        XCTAssertEqual(data.coachNotes(for: season.events[0].id).map(\.note), ["Great draws"])
        let filmStatus = try XCTUnwrap(data.assignmentStatus(film, now: now, calendar: calendar))
        data.setAssignment(film.id, done: true, periodStart: filmStatus.periodStart)
        base = try await parent.sync(local: data, base: base)

        // 3. The coach sees it done.
        var rosters = try await coach.coachWorkspace(now: now, calendar: calendar)
        var roster = try XCTUnwrap(rosters.first { $0.id == rosterID })
        XCTAssertEqual(Set(roster.assignments.map(\.id)), [film.id, reps.id])
        XCTAssertEqual(roster.completion(of: film, now: now, calendar: calendar)?.done, 1)
        XCTAssertEqual(roster.athletes.first?.data.coachNotes.first?.note, "Great draws")

        // 4. Unticking reaches the coach too; clearing the note removes it for the family.
        data = base.appData
        data.setAssignment(film.id, done: false, periodStart: filmStatus.periodStart)
        base = try await parent.sync(local: data, base: base)
        rosters = try await coach.coachWorkspace(now: now, calendar: calendar)
        roster = try XCTUnwrap(rosters.first { $0.id == rosterID })
        XCTAssertEqual(roster.completion(of: film, now: now, calendar: calendar)?.done, 0)
        try await coach.saveCoachNote(eventID: season.events[0].id, profileID: season.id, note: "  ")
        let cleared = try await parent.snapshot(profileID: season.id)
        XCTAssertEqual(cleared?.coachNotes.count, 0)

        // 5. A task the coach deletes goes from the family's phone at the next sync, with nothing left to send.
        try await coach.deleteAssignment(film.id)
        base = try await parent.sync(local: base.appData, base: base)
        XCTAssertEqual(base.appData.assignments.map(\.id), [reps.id])

        try await coach.deleteRoster(rosterID)
        try await parent.deleteProfile(season.id)
    }

    func testAthleteJoinsWithACodeAndLocksADoc() async throws {
        let season = Fixtures.season(name: "E2E family \(UUID().uuidString.prefix(6))")
        let parent = await sync(tokenA)
        let athlete = await sync(tokenB)
        let parentID = try userID(tokenA), athleteID = try userID(tokenB)
        var parentBase = try await parent.sync(local: season, base: nil)

        // 1. The parent invites the athlete's own login, and the athlete types the code in.
        let code = try await parent.createInvite(profileID: season.id, relationship: .athlete)
        let open = try await parent.openInvites(profileID: season.id)
        XCTAssertEqual(open.map(\.code), [code])
        let joined = try await athlete.acceptInvite(code: code.lowercased())
        XCTAssertEqual(joined, season.id)
        let stillOpen = try await parent.openInvites(profileID: season.id)
        XCTAssertTrue(stillOpen.isEmpty, "a used code isn't open")
        try await athlete.saveAccount(AccountRow(userID: athleteID, displayName: "Sam", kind: .athlete))
        let account = try await athlete.account(userID: athleteID)
        XCTAssertEqual(account?.kind, .athlete)
        let people = try await parent.people(profileID: season.id, me: parentID)
        XCTAssertEqual(people.map(\.access.role), [.owner, .editor])
        XCTAssertEqual(people.last?.displayName, "Sam")
        XCTAssertEqual(people.last?.access.relationships, [.athlete])
        XCTAssertEqual(people.first?.isMe, true)

        // 2. The athlete logs training, tries to change the budget, and locks the doc.
        let downloaded = try await athlete.snapshot(profileID: season.id)
        var athleteBase = try XCTUnwrap(downloaded)
        XCTAssertEqual(athleteBase.access, ProfileAccess(role: .editor, relationships: [.athlete]))
        var athleteData = athleteBase.appData
        athleteData.sessions[0].minutes = 100
        athleteData.expenses[0].amount = 1
        athleteData.docs[0].visibility = .locked
        athleteBase = try await athlete.sync(local: athleteData, base: athleteBase)
        XCTAssertEqual(athleteBase.docs.map(\.visibility), [.locked])
        XCTAssertEqual(athleteBase.appData.expenses.first { $0.id == season.expenses[0].id }?.amount, 1850, "athletes don't change the budget")

        // 3. The parent changed the doc meanwhile: the change is dropped and they see a placeholder instead.
        var parentData = parentBase.appData
        parentData.docs[0].status = .reviewed
        parentBase = try await parent.sync(local: parentData, base: parentBase)
        XCTAssertTrue(parentBase.docs.isEmpty)
        XCTAssertEqual(parentBase.lockedDocs.map(\.id), [season.docs[0].id])
        XCTAssertEqual(parentBase.appData.sessions.first { $0.id == season.sessions[0].id }?.minutes, 100)
        let athleteView = try await athlete.snapshot(profileID: season.id)
        XCTAssertEqual(athleteView?.docs.first?.status, .toReview, "the parent's change didn't reach the locked doc")
        XCTAssertEqual(athleteView?.lockedDocs, [], "the athlete gets the doc itself")

        // 4. The parent unlinks the athlete's login, then deletes the athlete.
        try await parent.removeMember(profileID: season.id, userID: athleteID)
        let unlinked = try await athlete.snapshot(profileID: season.id)
        XCTAssertNil(unlinked)
        try await parent.deleteProfile(season.id)
    }

    func testHockeyIsItsOwnProfileWithTheSameFamily() async throws {
        let lacrosse = Fixtures.season(name: "E2E two sports \(UUID().uuidString.prefix(6))")
        let owner = await sync(tokenA)
        let other = await sync(tokenB)
        let otherID = try userID(tokenB)
        _ = try await owner.sync(local: lacrosse, base: nil)
        let code = try await owner.createInvite(profileID: lacrosse.id, relationship: .parent)
        _ = try await other.acceptInvite(code: code)

        // 1. The owner adds hockey: its own profile, with the same family.
        var hockey = lacrosse.addingSport(.hockey)
        hockey.profile.shoots = .left
        hockey.programs = [Program(id: "kings", name: "Jr. Kings U15 AA", detail: "", group: .teams, sessionCategory: .team, monogram: "JK")]
        hockey.sessions = [TrainingSession(date: Fixtures.day(1), programID: "kings", category: .team, minutes: 75, effort: 7, focus: ["Faceoffs"])]
        let uploaded = try await owner.sync(local: hockey, base: nil)
        XCTAssertEqual(uploaded.profile.sport, .hockey)
        XCTAssertEqual(uploaded.profile.athleteKey, lacrosse.id)
        let added = try await owner.addFamilyToSport(profileID: hockey.id)
        XCTAssertEqual(added, 1, "the other parent comes along")

        let theirs = try await other.profiles()
        XCTAssertEqual(Set(theirs.filter { $0.athleteKey == lacrosse.id }.map(\.sport)), [.lacrosse, .hockey])
        let theirSnapshot = try await other.snapshot(profileID: hockey.id)
        let theirHockey = try XCTUnwrap(theirSnapshot)
        XCTAssertEqual(theirHockey.access, ProfileAccess(role: .editor, relationships: [.parent]))
        XCTAssertEqual(theirHockey.appData.sessions.map(\.focus), [["Faceoffs"]])
        XCTAssertEqual(theirHockey.appData.profile.shoots, .left)
        XCTAssertTrue(theirHockey.appData.wallballSessions.isEmpty, "nothing comes over from lacrosse")

        // 2. A hockey roster only takes the hockey profile.
        let rosterID = try await other.createRoster(name: "E2E U15 AA", kind: .team, sport: .hockey)
        let made = try await other.rosters()
        let rosterCode = try XCTUnwrap(made.first { $0.id == rosterID }?.joinCode)
        let info = try await owner.describeCode(rosterCode)
        guard case .roster("E2E U15 AA", .team, _, let sport) = info else { return XCTFail("\(info)") }
        XCTAssertEqual(sport, .hockey, "a roster's code says its sport")
        do {
            _ = try await owner.joinRoster(code: rosterCode, profileID: lacrosse.id)
            XCTFail("a lacrosse profile can't join a hockey roster")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("hockey"), error.localizedDescription)
        }
        let joined = try await owner.joinRoster(code: rosterCode, profileID: hockey.id)
        XCTAssertEqual(joined, rosterID)

        // 3. The other parent leaves from hockey and is off both sports.
        let left = try await other.removeMember(profileID: hockey.id, userID: otherID)
        XCTAssertEqual(Set(left), [lacrosse.id, hockey.id])
        let afterLeaving = try await other.profiles()
        XCTAssertFalse(afterLeaving.contains { $0.athleteKey == lacrosse.id })

        try await other.deleteRoster(rosterID)
        try await owner.deleteProfile(hockey.id)
        try await owner.deleteProfile(lacrosse.id)
    }
}
