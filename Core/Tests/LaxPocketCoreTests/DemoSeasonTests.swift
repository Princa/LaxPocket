import XCTest
@testable import LaxPocketCore

final class DemoSeasonTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_791_000_000) // Oct 2026
    let calendar = Calendar.laxWeek

    func testSameDayGivesSameData() {
        let shape = { (data: AppData) in data.sessions.map { "\($0.date) \($0.programID) \($0.minutes) \($0.effort)" } }
        XCTAssertEqual(shape(DemoSeason.make(now: now)), shape(DemoSeason.make(now: now)))
        XCTAssertEqual(DemoSeason.make(now: now).id, DemoSeason.profileID)
    }

    func testEverythingPointsAtSomethingThatExists() {
        let data = DemoSeason.make(now: now)
        let programIDs = Set(data.programs.map(\.id))
        XCTAssertTrue(programIDs.contains(AppData.ndtpProgramID))
        XCTAssertEqual(data.profile.benchmarkGroup, .u15Women)
        XCTAssertTrue(data.sessions.allSatisfy { programIDs.contains($0.programID) })
        XCTAssertTrue(data.expenses.compactMap(\.programID).allSatisfy(programIDs.contains))
        XCTAssertTrue(data.programBudgets.allSatisfy { programIDs.contains($0.programID) })
        let tripIDs = Set(data.trips.map(\.id))
        XCTAssertTrue(data.expenses.compactMap(\.tripID).allSatisfy(tripIDs.contains))
        let eventIDs = Set(data.events.map(\.id))
        XCTAssertEqual(data.trips.compactMap(\.eventID).filter(eventIDs.contains).count, 2)
        let drillIDs = Set(data.wallballLibrary.map(\.id))
        XCTAssertTrue(data.wallballSessions.allSatisfy { $0.sets.allSatisfy { drillIDs.contains($0.drillID) } })
    }

    func testFillsEveryScreenAroundNow() {
        let data = DemoSeason.make(now: now)
        XCTAssertTrue(data.sessions.allSatisfy { $0.date <= now })
        XCTAssertTrue(data.wallballSessions.allSatisfy { $0.date <= now })
        XCTAssertFalse(Workload.sessions(data.sessions, inWeekOf: now).isEmpty)
        XCTAssertTrue(data.sessions.contains { $0.category == .mental })
        XCTAssertGreaterThanOrEqual(Season.upcoming(data.events, from: now).count, 4)
        XCTAssertTrue(Season.past(data.events, from: now).contains { !$0.hasResult })
        XCTAssertGreaterThan(Season.record(for: data.events).gamesPlayed, 4)
        XCTAssertEqual(data.combineResults.count, 2)
        XCTAssertNotNil(BodyTrends.growthRate(data.bodyMeasurements))

        let season = AthleteProfile.seasonStart(for: now)
        XCTAssertTrue(data.expenses.allSatisfy { $0.season == season })
        XCTAssertTrue(data.expenses.contains { $0.currency == .usd })
        let budget = BudgetMath.season(season, in: data)
        XCTAssertEqual(budget.overall, 12_000)
        XCTAssertGreaterThan(budget.summary.spent, 0)
        XCTAssertLessThan(budget.summary.spent, budget.overall)
    }

    func testSurvivesSaving() throws {
        let data = DemoSeason.make(now: now)
        let decoded = try AppData.decoder.decode(AppData.self, from: AppData.encoder.encode(data))
        XCTAssertEqual(decoded, data)
    }

    // MARK: - Previewing each role

    func testEachRoleSeesMayaAsTheCloudWould() {
        let parent = DemoSeason.make(now: now, calendar: calendar, viewer: .parent)
        XCTAssertEqual(parent.access, ProfileAccess(role: .owner, relationships: [.parent]))
        XCTAssertFalse(parent.docs.contains { $0.folder == .journal }, "the journal is locked")
        XCTAssertEqual(parent.lockedDocs.map(\.folder), [.journal])

        let athlete = DemoSeason.make(now: now, calendar: calendar, viewer: .athlete)
        XCTAssertTrue(athlete.access?.canLockDocs == true)
        XCTAssertFalse(athlete.canWrite(.budget))
        XCTAssertEqual(athlete.docs.first { $0.folder == .journal }?.visibility, .locked)
        XCTAssertEqual(athlete.docs.first { $0.folder == .goals }?.visibility, .hidden)
        XCTAssertTrue(athlete.lockedDocs.isEmpty)

        XCTAssertNil(DemoSeason.make(now: now, calendar: calendar).access, "the plain demo stays local-only")
    }

    func testTeamRosterShowsOnlyWhatACoachSees() throws {
        let rosters = DemoSeason.coachRosters(kind: .team, now: now, calendar: calendar)
        let roster = try XCTUnwrap(rosters.first)
        XCTAssertEqual(roster.kind, .team)
        XCTAssertEqual(roster.athletes.map(\.data.profile.firstName), ["Ava", "Lily", "Nora", "Zoe"])
        XCTAssertEqual(Set(roster.athletes.map(\.id)).count, 4)
        for athlete in roster.athletes {
            let data = athlete.data
            XCTAssertFalse(data.sessions.isEmpty || data.events.isEmpty, data.profile.firstName)
            XCTAssertFalse(data.sessions.contains { $0.category == .mental }, "no mental sessions for a team coach")
            XCTAssertTrue(data.docs.isEmpty && data.lockedDocs.isEmpty)
            XCTAssertTrue(data.expenses.isEmpty && data.trips.isEmpty && data.bodyMeasurements.isEmpty)
            XCTAssertEqual(data.access, ProfileAccess(role: .viewer, relationships: [.coach]))
        }
        let flags = Dictionary(uniqueKeysWithValues: roster.athletes.map { ($0.data.profile.firstName, $0.week(now: now, calendar: calendar).flags) })
        // Each athlete shows one thing to notice, and only that.
        XCTAssertEqual(flags["Ava"], [.highLoad])
        XCTAssertEqual(flags["Lily"], [.laggingHand(.left)])
        XCTAssertEqual(flags["Nora"]?.count, 1)
        if case .quiet(let days)? = flags["Nora"]?.first { XCTAssertGreaterThanOrEqual(days, 6) } else { XCTFail("Nora is quiet") }
        XCTAssertEqual(flags["Zoe"], [])
    }

    func testMentalRosterShowsTheMentalGame() throws {
        let roster = try XCTUnwrap(DemoSeason.coachRosters(kind: .mental, now: now, calendar: calendar).first)
        XCTAssertEqual(roster.athletes.count, 3)
        let ava = try XCTUnwrap(roster.athletes.first { $0.data.profile.firstName == "Ava" }).data
        let lily = try XCTUnwrap(roster.athletes.first { $0.data.profile.firstName == "Lily" }).data
        XCTAssertTrue(ava.sessions.contains { $0.category == .mental })
        XCTAssertEqual(ava.docs.first { $0.folder == .journal }?.visibility, .locked, "Ava trusted her mental coach")
        XCTAssertFalse(lily.docs.contains { $0.folder == .journal })
        XCTAssertEqual(lily.lockedDocs.map(\.folder), [.journal], "Lily didn't")
        XCTAssertTrue(ava.canRead(.mental) && !ava.canRead(.budget))
    }

    func testPreviewsHaveTasksAndNotes() throws {
        // In the evening, after the day's wall ball.
        let evening = try XCTUnwrap(calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now))
        let athlete = DemoSeason.make(now: evening, calendar: calendar, viewer: .athlete)
        let statuses = athlete.assignmentStatuses(now: evening, calendar: calendar)
        XCTAssertEqual(statuses.count, 5, "three from the team coach, two from the mental coach")
        XCTAssertTrue(statuses.contains { $0.assignment.kind == .wallball && $0.logged ?? 0 > 0 }, "wall ball counts what's logged")
        let game = try XCTUnwrap(Season.results(athlete.events).first)
        XCTAssertEqual(athlete.coachNotes(for: game.id).count, 1)

        let team = try XCTUnwrap(DemoSeason.coachRosters(kind: .team, now: now, calendar: calendar).first)
        XCTAssertEqual(team.assignments.count, 4)
        let film = try XCTUnwrap(team.assignments.first { $0.title.hasPrefix("Watch") })
        XCTAssertEqual(team.completion(of: film, now: now, calendar: calendar)?.done, 2, "Ava and Zoe ticked it off")
        let checkIn = try XCTUnwrap(team.assignments.first { $0.profileID != nil })
        XCTAssertEqual(team.completion(of: checkIn, now: now, calendar: calendar)?.of, 1, "for one athlete")
        XCTAssertEqual(team.athletes.filter { !$0.data.coachNotes.isEmpty }.count, 2)
    }
}
