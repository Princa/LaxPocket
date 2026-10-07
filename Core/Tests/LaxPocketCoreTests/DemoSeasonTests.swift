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
        for data in DemoSeason.profiles(now: now, calendar: calendar) {
            let decoded = try AppData.decoder.decode(AppData.self, from: AppData.encoder.encode(data))
            XCTAssertEqual(decoded, data, data.profile.sport.title)
        }
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

    // MARK: - Hockey

    func testHockeyIsMayasSecondSport() {
        let profiles = DemoSeason.profiles(now: now, calendar: calendar)
        XCTAssertEqual(profiles.map(\.profile.sport), [.lacrosse, .hockey])
        XCTAssertEqual(profiles.map(\.id), [DemoSeason.profileID, DemoSeason.hockeyProfileID])
        let hockey = profiles[1]
        XCTAssertEqual(hockey.athleteKey, DemoSeason.profileID, "the same athlete as her lacrosse profile")
        XCTAssertTrue(hockey.isDemo && hockey.summary.isDemo, "stays on the phone")
        XCTAssertEqual(hockey.profile.firstName, "Maya")
        XCTAssertEqual(hockey.profile.weeklyShotGoal, 1_000)
        XCTAssertEqual(ProfileIndex(profiles: profiles.map(\.summary), activeProfileID: hockey.id).athletes.count, 1)

        // Nothing lacrosse-only, and nothing added up from her lacrosse season.
        XCTAssertTrue(hockey.wallballSessions.isEmpty && hockey.wallballDrills.isEmpty && hockey.combineResults.isEmpty)
        XCTAssertNil(hockey.profile.benchmarkGroup)
        XCTAssertTrue(hockey.events.allSatisfy { $0.stats == nil }, "hockey games take a score until their stat sheets come")
        XCTAssertNotEqual(hockey.themeID, profiles[0].themeID)

        let programIDs = Set(hockey.programs.map(\.id))
        XCTAssertTrue(hockey.sessions.allSatisfy { programIDs.contains($0.programID) })
        XCTAssertTrue(hockey.expenses.compactMap(\.programID).allSatisfy(programIDs.contains))
        XCTAssertTrue(hockey.programBudgets.allSatisfy { programIDs.contains($0.programID) })
        let tripIDs = Set(hockey.trips.map(\.id))
        XCTAssertTrue(hockey.expenses.compactMap(\.tripID).allSatisfy(tripIDs.contains))
        let eventIDs = Set(hockey.events.map(\.id))
        XCTAssertEqual(hockey.trips.compactMap(\.eventID).filter(eventIDs.contains).count, 2)
        let tags = Set(hockey.profile.focusOptions + TrainingSession.mentalFocusOptions)
        XCTAssertTrue(hockey.sessions.allSatisfy { $0.focus.allSatisfy(tags.contains) }, "hockey focus tags")
        let drillIDs = Set(hockey.practiceLibrary.map(\.id))
        XCTAssertTrue(hockey.practiceSessions.allSatisfy { session in
            session.sets.allSatisfy { drillIDs.contains($0.drillID) && PracticeSet.amountRange.contains($0.amount) && ($0.onTarget ?? 0) <= $0.amount }
        })
    }

    func testHockeyFillsEveryScreenAroundNow() throws {
        let hockey = DemoSeason.make(sport: .hockey, now: now, calendar: calendar)
        XCTAssertTrue(hockey.sessions.allSatisfy { $0.date <= now })
        XCTAssertTrue(hockey.practiceSessions.allSatisfy { $0.date <= now })
        XCTAssertFalse(Workload.sessions(hockey.sessions, inWeekOf: now).isEmpty)
        XCTAssertTrue(hockey.sessions.contains { $0.category == .mental })
        XCTAssertGreaterThanOrEqual(Season.upcoming(hockey.events, from: now).count, 4)
        XCTAssertTrue(Season.past(hockey.events, from: now).contains { !$0.hasResult })
        XCTAssertGreaterThan(Season.record(for: hockey.events).gamesPlayed, 4)
        XCTAssertEqual(Set(hockey.docs.map(\.folder)).count, 4)
        XCTAssertNotNil(BodyTrends.growthRate(hockey.bodyMeasurements))

        // On pace for the weekly goals lately, every day, and a challenge each week.
        let library = hockey.practiceLibrary
        let today = calendar.startOfDay(for: now)
        let lastSevenDays = PracticeStats.sessions(hockey.practiceSessions, from: today.addingTimeInterval(-7 * 86_400), to: today)
        let totals = PracticeStats.totals(lastSevenDays, library: library)
        XCTAssertEqual(Double(totals.shots), Double(hockey.profile.weeklyShotGoal), accuracy: 200)
        XCTAssertNotNil(totals.accuracy)
        let hands = PracticeStats.byKind(lastSevenDays, library: library)[.stickhandling]?.wholeMinutes ?? 0
        XCTAssertGreaterThanOrEqual(hands, hockey.profile.weeklyStickhandlingGoal)
        XCTAssertGreaterThanOrEqual(PracticeStats.streak(hockey.practiceSessions, today: now, calendar: calendar), 6)
        XCTAssertEqual(PracticeStats.challengeLengths(hockey.practiceSessions), [30])
        // Her backhand trails, as her left hand does at wall ball.
        XCTAssertTrue(PracticeStats.backhandBehind(PracticeStats.byDrill(lastSevenDays, library: library)))

        let season = AthleteProfile.seasonStart(for: now)
        XCTAssertTrue(hockey.expenses.allSatisfy { $0.season == season })
        let budget = BudgetMath.season(season, in: hockey)
        XCTAssertEqual(budget.overall, 9_000)
        XCTAssertGreaterThan(budget.summary.spent, 0)
        XCTAssertLessThan(budget.summary.spent, budget.overall)
    }

    func testHockeyPreviewsHaveHockeyTasksAndNotes() throws {
        // In the evening, after the day's practice.
        let evening = try XCTUnwrap(calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now))
        let athlete = DemoSeason.make(sport: .hockey, now: evening, calendar: calendar, viewer: .athlete)
        XCTAssertEqual(athlete.access, ProfileAccess(role: .editor, relationships: [.athlete]))
        XCTAssertEqual(athlete.docs.first { $0.folder == .journal }?.visibility, .locked)
        let statuses = athlete.assignmentStatuses(now: evening, calendar: calendar)
        XCTAssertEqual(statuses.count, 6, "four from the hockey coach, two from the mental coach")
        let kinds = AssignmentKind.available(for: .hockey)
        XCTAssertTrue(statuses.allSatisfy { kinds.contains($0.assignment.kind) }, "no wall ball")
        XCTAssertTrue(statuses.contains { $0.assignment.kind == .shots && $0.logged ?? 0 > 0 }, "shots count what's logged")
        XCTAssertTrue(statuses.contains { $0.assignment.kind == .stickhandling && $0.logged ?? 0 > 0 })
        let game = try XCTUnwrap(Season.results(athlete.events).first)
        XCTAssertEqual(athlete.coachNotes(for: game.id).map(\.coachName), ["Coach Novak"])

        let parent = DemoSeason.make(sport: .hockey, now: now, calendar: calendar, viewer: .parent)
        XCTAssertEqual(parent.access, ProfileAccess(role: .owner, relationships: [.parent]))
        XCTAssertEqual(parent.lockedDocs.map(\.folder), [.journal])
    }

    func testHockeyTeamRosterShowsOnlyHockey() throws {
        let roster = try XCTUnwrap(DemoSeason.coachRosters(kind: .team, sport: .hockey, now: now, calendar: calendar).first)
        XCTAssertEqual(roster.sport, .hockey)
        XCTAssertEqual(roster.athletes.map(\.data.profile.firstName), ["Chloe", "Emma", "Grace", "Hannah"])
        for athlete in roster.athletes {
            let data = athlete.data
            XCTAssertEqual(data.profile.sport, .hockey)
            XCTAssertFalse(data.isDemo, "teammates aren't Maya")
            XCTAssertFalse(data.sessions.isEmpty || data.events.isEmpty || data.practiceSessions.isEmpty, data.profile.firstName)
            XCTAssertFalse(data.sessions.contains { $0.category == .mental }, "no mental sessions for a team coach")
            XCTAssertTrue(data.wallballSessions.isEmpty && data.docs.isEmpty && data.expenses.isEmpty && data.bodyMeasurements.isEmpty)
            XCTAssertEqual(data.access, ProfileAccess(role: .viewer, relationships: [.coach]))
        }
        XCTAssertEqual(roster.athletes.filter(\.data.profile.playsGoal).map(\.data.profile.firstName), ["Hannah"])
        let weeks = Dictionary(uniqueKeysWithValues: roster.athletes.map { ($0.data.profile.firstName, $0.week(now: now, calendar: calendar)) })
        // Each athlete shows one thing to notice, and only that.
        XCTAssertEqual(weeks["Chloe"]?.flags, [.highLoad])
        XCTAssertEqual(weeks["Emma"]?.flags, [.backhandBehind])
        XCTAssertEqual(weeks["Hannah"]?.flags.count, 1)
        if case .quiet(let days)? = weeks["Hannah"]?.flags.first { XCTAssertGreaterThanOrEqual(days, 6) } else { XCTFail("Hannah is quiet") }
        XCTAssertEqual(weeks["Grace"]?.flags, [])
        XCTAssertGreaterThan(weeks["Grace"]?.practice.shots ?? 0, 0)
        XCTAssertGreaterThan(weeks["Grace"]?.stickhandlingMinutes ?? 0, 0)

        XCTAssertEqual(roster.assignments.count, 5)
        XCTAssertTrue(roster.assignments.allSatisfy { AssignmentKind.available(for: .hockey).contains($0.kind) })
        let film = try XCTUnwrap(roster.assignments.first { $0.title.hasPrefix("Watch") })
        XCTAssertEqual(roster.completion(of: film, now: now, calendar: calendar)?.done, 2, "Chloe and Grace ticked it off")
        let shots = try XCTUnwrap(roster.assignments.first { $0.kind == .shots })
        XCTAssertEqual(roster.completion(of: shots, now: now, calendar: calendar)?.of, 4)
        XCTAssertEqual(roster.athletes.filter { !$0.data.coachNotes.isEmpty }.count, 2)

        // The lacrosse roster is a different team: no athlete, task or roster in common.
        let lacrosse = try XCTUnwrap(DemoSeason.coachRosters(kind: .team, now: now, calendar: calendar).first)
        XCTAssertNotEqual(lacrosse.id, roster.id)
        XCTAssertTrue(Set(lacrosse.athletes.map(\.id)).isDisjoint(with: roster.athletes.map(\.id)))
        XCTAssertTrue(Set(lacrosse.assignments.map(\.id)).isDisjoint(with: roster.assignments.map(\.id)))
    }

    func testHockeyMentalRosterShowsTheMentalGame() throws {
        let roster = try XCTUnwrap(DemoSeason.coachRosters(kind: .mental, sport: .hockey, now: now, calendar: calendar).first)
        XCTAssertEqual(roster.sport, .hockey)
        XCTAssertEqual(roster.kind, .mental)
        XCTAssertEqual(roster.athletes.count, 3)
        let chloe = try XCTUnwrap(roster.athletes.first { $0.data.profile.firstName == "Chloe" }).data
        let emma = try XCTUnwrap(roster.athletes.first { $0.data.profile.firstName == "Emma" }).data
        XCTAssertTrue(chloe.sessions.contains { $0.category == .mental })
        XCTAssertEqual(chloe.docs.first { $0.folder == .journal }?.visibility, .locked, "Chloe trusted her mental coach")
        XCTAssertFalse(emma.docs.contains { $0.folder == .journal })
        XCTAssertEqual(emma.lockedDocs.map(\.folder), [.journal], "Emma didn't")
        XCTAssertTrue(chloe.canRead(.mental) && !chloe.canRead(.budget))
        XCTAssertEqual(roster.assignments.map(\.title).sorted(), ["Visualisation", "Write your next-shift reset"])
    }
}
