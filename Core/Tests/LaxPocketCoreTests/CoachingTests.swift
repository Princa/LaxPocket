import XCTest
@testable import LaxPocketCore

final class CoachingTests: XCTestCase {
    private let calendar = Calendar.laxWeek
    /// A Thursday evening, a few days into the fixture season.
    private var now: Date { Fixtures.day(3, hour: 20) }

    /// Mirrors private.roster_sections: a team roster reads as a coach, a mental roster as a mental coach.
    func testRosterKindsReadLikeTheirRelationship() {
        XCTAssertEqual(RosterKind.team.relationship.readableSections, [.training, .events])
        XCTAssertEqual(RosterKind.mental.relationship.readableSections, [.training, .events, .mental])
    }

    func testWeekSummary() {
        var data = Fixtures.season()
        data.profile.weeklyGoalHours = 10
        let week = CoachWeek(data, now: now, calendar: calendar)
        let thisWeek = Workload.sessions(data.sessions, inWeekOf: now, calendar: calendar)
        XCTAssertEqual(week.hours, Workload.hours(for: thisWeek))
        XCTAssertEqual(week.goalFraction, week.hours.total / 10, accuracy: 0.0001)
        XCTAssertNil(week.loadRatio, "no earlier weeks to compare with")
        XCTAssertEqual(week.nextEvent?.title, "Fall showcase")
        XCTAssertEqual(week.lastResult?.title, "vs Rivals")
        XCTAssertGreaterThan(week.wallball.total, 0)
        XCTAssertTrue(week.flags.isEmpty)
    }

    func testFlags() {
        var data = Fixtures.season()
        // A light month, then a big week: the ratio jumps.
        for weeksAgo in 1...4 {
            data.sessions.append(TrainingSession(date: Fixtures.day(-7 * weeksAgo), programID: "club", category: .team, minutes: 30, effort: 5))
        }
        data.wallballSessions = [WallballSession(date: Fixtures.day(2, hour: 7), sets: [
            WallballSet(drillID: "overhand", hand: .right, reps: 90), WallballSet(drillID: "overhand", hand: .left, reps: 10)
        ])]
        let week = CoachWeek(data, now: now, calendar: calendar)
        XCTAssertEqual(week.zone, .high)
        XCTAssertEqual(week.flags, [.highLoad, .laggingHand(.left)])

        let later = CoachWeek(data, now: Fixtures.day(9, hour: 20), calendar: calendar)
        XCTAssertTrue(later.flags.contains(.quiet(days: 7)), "nothing since day 2")
        XCTAssertEqual(CoachWeek.Flag.quiet(days: 7).title, "Nothing logged in 7 days")
    }

    func testCodeInfoDecodes() throws {
        let invite = try JSONDecoder().decode(CodeInfo.self, from: Data(#"{"type":"invite","athlete":"Sam","relationship":"athlete"}"#.utf8))
        XCTAssertEqual(invite, .invite(athleteName: "Sam", relationship: .athlete))
        let roster = try JSONDecoder().decode(CodeInfo.self, from: Data(#"{"type":"roster","roster":"U15","kind":"mental","coach":"Dr G"}"#.utf8))
        XCTAssertEqual(roster, .roster(name: "U15", kind: .mental, coachName: "Dr G"))
        XCTAssertThrowsError(try JSONDecoder().decode(CodeInfo.self, from: Data(#"{"type":"coupon"}"#.utf8)))
    }

    func testWorkspaceGroupsAthletesByRoster() {
        let sam = Fixtures.season(name: "Sam"), alex = Fixtures.season(name: "Alex")
        let team = RosterRow(id: UUID(), kind: .team, name: "U15", joinCode: "ABCD2345")
        let mental = RosterRow(id: UUID(), kind: .mental, name: "Clients", joinCode: nil)
        let samRows = ProfileSnapshot(sam), alexRows = ProfileSnapshot(alex)
        var rows = CoachWorkspace.Rows()
        rows.profiles = [sam, alex].map {
            CoachAthleteProfileRow(id: $0.id, firstName: $0.profile.firstName, classYear: $0.profile.classYear, positions: $0.profile.positions,
                                   benchmarkGroup: $0.profile.benchmarkGroup, weeklyGoalHours: $0.profile.weeklyGoalHours, themeID: $0.themeID)
        }
        rows.sessions = samRows.sessions + alexRows.sessions
        rows.wallballSessions = samRows.wallballSessions.map(\.session)
        rows.wallballSets = samRows.wallballSessions.flatMap(\.sets)
        rows.events = samRows.events.map(\.event)
        rows.reflections = samRows.events.compactMap(\.reflection)
        rows.docs = samRows.docs
        let places = [RosterAthleteRow(rosterID: team.id, profileID: sam.id), RosterAthleteRow(rosterID: team.id, profileID: alex.id),
                      RosterAthleteRow(rosterID: mental.id, profileID: sam.id)]

        let rosters = CoachWorkspace.assemble(rosters: [team, mental], places: places, rows: rows)
        XCTAssertEqual(rosters.map(\.name), ["U15", "Clients"])
        XCTAssertEqual(rosters[0].athletes.map(\.data.profile.firstName), ["Alex", "Sam"], "by name")
        XCTAssertEqual(rosters[1].athletes.map(\.id), [sam.id])
        XCTAssertNil(rosters[1].joinCode)
        let coached = rosters[1].athletes[0].data
        XCTAssertEqual(coached.sessions.count, sam.sessions.count)
        XCTAssertEqual(coached.wallballSessions.map(\.reps.total), sam.wallballSessions.map(\.reps.total))
        XCTAssertEqual(coached.events.first { $0.id == sam.events[0].id }?.reflection?.wentWell, "Draws")
        XCTAssertEqual(coached.docs.count, 1)
        XCTAssertTrue(coached.expenses.isEmpty && coached.bodyMeasurements.isEmpty)
        XCTAssertEqual(coached.access, ProfileAccess(role: .viewer, relationships: [.coach, .mentalCoach]))
        XCTAssertEqual(rosters[0].athletes[0].data.access?.relationships, [.coach])
    }
}
