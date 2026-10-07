import XCTest
@testable import LaxPocketCore

final class AssignmentTests: XCTestCase {
    private let calendar = Calendar.laxWeek
    private let season = Fixtures.season()
    private let roster = UUID()

    private func day(_ offset: Int) -> DayKey { DayKey(Fixtures.day(offset), calendar: calendar) }

    func testDayKeys() throws {
        XCTAssertEqual(DayKey("2026-10-05"), DayKey(year: 2026, month: 10, day: 5))
        XCTAssertNil(DayKey("2026-13-01"))
        XCTAssertNil(DayKey("yesterday"))
        XCTAssertEqual(DayKey(year: 2026, month: 3, day: 7).description, "2026-03-07")
        XCTAssertEqual(try JSONDecoder().decode(DayKey.self, from: Data(#""2026-10-05T00:00:00+00:00""#.utf8)), DayKey("2026-10-05"))
        XCTAssertEqual(String(data: try JSONEncoder().encode(DayKey("2026-10-05")!), encoding: .utf8), #""2026-10-05""#)
        XCTAssertLessThan(DayKey("2026-09-30")!, DayKey("2026-10-01")!)
    }

    func testPeriods() throws {
        let daily = Assignment(rosterID: roster, kind: .wallball, title: "Reps", schedule: .daily, startsOn: day(0), endsOn: day(5), targetReps: 100)
        XCTAssertNil(daily.period(containing: Fixtures.day(-1), calendar: calendar), "not started")
        XCTAssertEqual(daily.period(containing: Fixtures.day(2), calendar: calendar)?.start, day(2))
        XCTAssertNil(daily.period(containing: Fixtures.day(6), calendar: calendar), "ended")

        let weekly = Assignment(rosterID: roster, kind: .training, title: "Skills", schedule: .weekly, startsOn: day(0), targetMinutes: 120)
        let week = try XCTUnwrap(weekly.period(containing: Fixtures.day(3), calendar: calendar))
        XCTAssertEqual(week.interval.start, Workload.startOfWeek(for: Fixtures.day(3), calendar: calendar))
        XCTAssertEqual(week.interval.duration, 7 * 86_400, accuracy: 3_600)
        XCTAssertNotNil(weekly.period(containing: Fixtures.day(300), calendar: calendar), "ongoing")

        let once = Assignment(rosterID: roster, kind: .check, title: "Film", schedule: .once, startsOn: day(0), dueOn: day(3))
        XCTAssertEqual(once.period(containing: Fixtures.day(3, hour: 23), calendar: calendar)?.start, day(0), "the whole span is one period")
        XCTAssertNil(once.period(containing: Fixtures.day(4), calendar: calendar), "past the due date")
        XCTAssertEqual(once.summary(calendar: calendar).hasPrefix("Tick off by "), true)
        XCTAssertEqual(weekly.summary(), "2 h of training every week")
        XCTAssertEqual(daily.summary(), "100 wall ball reps every day")
    }

    func testProgressComesFromWhatsLogged() throws {
        var data = season
        let reps = Assignment(rosterID: roster, kind: .wallball, title: "Reps", schedule: .daily, startsOn: day(-1), targetReps: 50)
        let team = Assignment(rosterID: roster, kind: .training, title: "Team", schedule: .weekly, startsOn: day(-10), targetMinutes: 120,
                              category: .team)
        let film = Assignment(rosterID: roster, kind: .check, title: "Film", schedule: .once, startsOn: day(0), dueOn: day(4))
        let elsewhere = Assignment(rosterID: roster, profileID: UUID(), kind: .check, title: "Someone else's", schedule: .once,
                                   startsOn: day(0), dueOn: day(4))
        data.assignments = [reps, team, film, elsewhere]

        let now = Fixtures.day(0, hour: 21)
        let statuses = data.assignmentStatuses(now: now, calendar: calendar)
        XCTAssertEqual(statuses.map(\.assignment.title), ["Film", "Reps", "Team"], "one-off first, then daily, then weekly; not other athletes'")
        let wallball = try XCTUnwrap(statuses.first { $0.assignment.id == reps.id })
        // The fixture's days don't start at midnight, so count what falls in the task's day.
        let today = WallballStats.reps(season.wallballSessions.filter { wallball.period.contains($0.date) && $0.date < wallball.period.end }).total
        XCTAssertGreaterThan(today, 50)
        XCTAssertEqual(wallball.logged, today)
        XCTAssertTrue(wallball.isDone)
        XCTAssertEqual(wallball.progressText, "\(today) / 50 reps")
        let training = try XCTUnwrap(statuses.first { $0.assignment.id == team.id })
        XCTAssertEqual(training.logged, Workload.sessions(season.sessions, inWeekOf: now, calendar: calendar)
            .filter { $0.category == .team && $0.date <= now }.reduce(0) { $0 + $1.minutes })
        XCTAssertFalse(training.isDone)
        XCTAssertEqual(training.progressText, "1 h 30 min of 2 h")
        let tick = try XCTUnwrap(statuses.first { $0.assignment.id == film.id })
        XCTAssertFalse(tick.isDone)

        data.setAssignment(film.id, done: true, periodStart: tick.periodStart)
        data.setAssignment(team.id, done: true, periodStart: training.periodStart)
        let after = data.assignmentStatuses(now: now, calendar: calendar)
        XCTAssertTrue(after.allSatisfy(\.isDone), "ticked off by hand")
        XCTAssertEqual(after.first { $0.assignment.id == film.id }?.progressText, "Done")
        data.setAssignment(film.id, done: false, periodStart: tick.periodStart)
        XCTAssertFalse(data.assignmentStatus(film, now: now, calendar: calendar)!.isDone)

        // Tomorrow is a new day for the daily task.
        XCTAssertEqual(data.assignmentStatus(reps, now: Fixtures.day(1, hour: 21), calendar: calendar)?.periodStart, day(1))
    }

    func testRowsKeepToWhatTheDatabaseTakes() {
        let messy = Assignment(rosterID: roster, kind: .wallball, title: "  ", schedule: .once, startsOn: day(5), dueOn: day(1), endsOn: day(9),
                               targetReps: 50_000, targetMinutes: 30, category: .skills)
        let row = AssignmentRow(messy)
        XCTAssertEqual(row.title, "Wall ball reps")
        XCTAssertEqual(row.dueOn, day(5), "not before it starts")
        XCTAssertNil(row.endsOn)
        XCTAssertEqual(row.targetReps, 10_000)
        XCTAssertNil(row.targetMinutes)
        XCTAssertNil(row.category)
        let weekly = AssignmentRow(Assignment(rosterID: roster, kind: .training, title: "Run", schedule: .weekly, startsOn: day(0), dueOn: day(3),
                                              targetMinutes: 90, category: .fitness))
        XCTAssertNil(weekly.dueOn)
        XCTAssertEqual(weekly.category, .fitness)
        XCTAssertEqual(weekly.targetMinutes, 90)
    }

    func testTicksSyncAndTasksAreTheCloudsCopy() {
        let task = Assignment(rosterID: roster, profileID: season.id, rosterName: "U15", coachName: "Coach", kind: .check, title: "Film",
                              schedule: .once, startsOn: day(0), dueOn: day(3))
        var cloudData = season
        cloudData.assignments = [task]
        cloudData.access = ProfileAccess(role: .editor, relationships: [.athlete])
        let remote = ProfileSnapshot(cloudData)

        var local = cloudData
        local.setAssignment(task.id, done: true, periodStart: day(0))
        let outcome = ProfileMerge.merge(base: remote, local: ProfileSnapshot(local), remote: remote)
        XCTAssertEqual(outcome.changes.assignmentCompletions.upserts.map(\.periodStart), [day(0)])
        XCTAssertEqual(outcome.merged.appData.assignments, [task])

        // The coach removed the task: the tick is neither sent nor deleted, and the task goes.
        var gone = cloudData
        gone.assignments = []
        let after = ProfileMerge.merge(base: remote, local: ProfileSnapshot(local), remote: ProfileSnapshot(gone))
        XCTAssertTrue(after.changes.assignmentCompletions.isEmpty)
        XCTAssertTrue(after.merged.appData.assignments.isEmpty)
        XCTAssertTrue(after.merged.assignmentCompletions.isEmpty)

        // A coach (read only) never sends ticks.
        var coachView = cloudData
        coachView.access = ProfileAccess(role: .viewer, relationships: [.coach])
        let coach = ProfileMerge.merge(base: remote, local: ProfileSnapshot(local), remote: ProfileSnapshot(coachView))
        XCTAssertTrue(coach.changes.isEmpty)
    }

    func testSnapshotKeepsTasksTicksAndNotes() {
        var data = season
        data.assignments = [Assignment(rosterID: roster, profileID: data.id, rosterName: "U15", coachName: "Coach", kind: .training, title: "Run",
                                       schedule: .weekly, startsOn: day(0), targetMinutes: 90, category: .fitness)]
        data.assignmentCompletions = [AssignmentCompletion(assignmentID: data.assignments[0].id, periodStart: day(0))]
        data.coachNotes = [CoachNote(eventID: data.events[0].id, coachID: UUID(), coachName: "Coach", note: "Great draws",
                                     updatedAt: Date(timeIntervalSince1970: 1_790_000_000))]
        XCTAssertEqual(ProfileSnapshot(data).appData, data)
        XCTAssertEqual(data.coachNotes(for: data.events[0].id).map(\.note), ["Great draws"])
    }

    func testRosterCompletion() {
        var sam = season
        var alex = Fixtures.season(name: "Alex")
        let task = Assignment(rosterID: roster, kind: .check, title: "Film", schedule: .once, startsOn: day(0), dueOn: day(3))
        sam.assignments = [task]
        alex.assignments = [task]
        sam.setAssignment(task.id, done: true, periodStart: day(0))
        let team = CoachRoster(id: roster, name: "U15", kind: .team, joinCode: nil, athletes: [CoachAthlete(data: sam), CoachAthlete(data: alex)],
                               assignments: [task])
        let counts = team.completion(of: task, now: Fixtures.day(1), calendar: calendar)
        XCTAssertEqual(counts?.done, 1)
        XCTAssertEqual(counts?.of, 2)
        XCTAssertNil(team.completion(of: task, now: Fixtures.day(10), calendar: calendar), "over")
    }
}
