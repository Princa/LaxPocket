import XCTest
@testable import LaxPocketCore

final class PracticeTests: XCTestCase {
    /// The fixture's days are UTC days (hours 1 to 9 stay inside one), so the tests pass in any time zone.
    private let calendar: Calendar = {
        var calendar = Calendar.laxWeek
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let library = PracticeCatalog.hockey

    /// A made-up hockey profile with a few days of practice.
    private func hockey() -> AppData {
        var data = Fixtures.season().addingSport(.hockey, now: Fixtures.day(0))
        data.practiceSessions = [
            PracticeSession(date: Fixtures.day(0, hour: 5), sets: [
                PracticeSet(drillID: "wrist-shot", amount: 100, onTarget: 60),
                PracticeSet(drillID: "backhand", amount: 20),
                PracticeSet(drillID: "quick-hands", amount: 10)
            ], minutes: 30),
            PracticeSession(date: Fixtures.day(1, hour: 5), sets: [
                PracticeSet(drillID: "snap-shot", amount: 50, onTarget: 20),
                PracticeSet(drillID: "forehand-pass", amount: 40),
                PracticeSet(drillID: "figure-eights", amount: 5)
            ]),
            // A 30-second quick-hands challenge: 85 touches, half a minute of stickhandling.
            PracticeSession(date: Fixtures.day(1, hour: 6), sets: [PracticeSet(drillID: "quick-hands", amount: 85)], challengeSeconds: 30)
        ]
        return data
    }

    func testCatalogAndLibrary() {
        XCTAssertEqual(PracticeCatalog.drills(for: .hockey).count, 17)
        XCTAssertTrue(PracticeCatalog.drills(for: .lacrosse).isEmpty, "lacrosse has wall ball instead")
        XCTAssertEqual(Set(library.map(\.kind)), [.shooting, .stickhandling, .passing])
        XCTAssertTrue(library.filter { $0.kind == .shooting }.allSatisfy { $0.measure == .shots && $0.tracksTarget })
        XCTAssertTrue(library.filter { $0.kind == .stickhandling }.allSatisfy { $0.measure == .minutes && !$0.tracksTarget })

        var changed = PracticeCatalog.builtIn(id: "slap-shot")!
        changed.isHidden = true
        let own = PracticeDrill(name: "Tarp corners", kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 40)
        let mine = PracticeCatalog.library([own, changed], sport: .hockey)
        XCTAssertEqual(mine.count, 18)
        XCTAssertEqual(mine.last, own, "the athlete's own drills come after the built-ins")
        XCTAssertEqual(mine.first { $0.id == "slap-shot" }?.isHidden, true)
        XCTAssertFalse(own.isBuiltIn)
        XCTAssertFalse(PracticeDrill(name: "Odd", kind: .stickhandling, measure: .minutes, tracksTarget: true, defaultAmount: 5).tracksTarget,
                       "only shots count on target")
    }

    func testSetsAreNormalized() {
        let sets = PracticeSession.normalized([
            PracticeSet(drillID: "wrist-shot", amount: 30, onTarget: 20),
            PracticeSet(drillID: "backhand", amount: 0),
            PracticeSet(drillID: "wrist-shot", amount: 20, onTarget: 40)
        ])
        XCTAssertEqual(sets, [PracticeSet(drillID: "wrist-shot", amount: 50, onTarget: 50)], "repeats add up, on target stays within the shots")
    }

    func testTotalsByMeasureKindAndDrill() {
        let data = hockey()
        let totals = PracticeStats.totals(data.practiceSessions, library: library)
        XCTAssertEqual(totals.shots, 170)
        XCTAssertEqual(totals.onTarget, 80)
        XCTAssertEqual(totals.shotsCounted, 150, "the backhands weren't counted on target")
        XCTAssertEqual(try XCTUnwrap(totals.accuracy), 80.0 / 150, accuracy: 0.0001)
        XCTAssertEqual(totals.reps, 40)
        XCTAssertEqual(totals.minutes, 15.5, accuracy: 0.0001, "a challenge adds its time, not its touches")

        let byKind = PracticeStats.byKind(data.practiceSessions, library: library)
        XCTAssertEqual(byKind[.stickhandling]?.wholeMinutes, 16)
        XCTAssertEqual(byKind[.shooting]?.shots, 170)
        XCTAssertEqual(byKind[.passing]?.reps, 40)
        let byDrill = PracticeStats.byDrill(data.practiceSessions, library: library)
        XCTAssertEqual(byDrill["quick-hands"]?.minutes ?? 0, 10.5, accuracy: 0.0001)
        XCTAssertEqual(byDrill["wrist-shot"]?.shots, 100)
    }

    func testDaysWeeksStreakAndBestDay() {
        let data = hockey()
        let days = PracticeStats.days(endingOn: Fixtures.day(2, hour: 1), count: 3, sessions: data.practiceSessions, library: library,
                                      calendar: calendar)
        XCTAssertEqual(days.map(\.totals.shots), [120, 50, 0])
        let weeks = PracticeStats.weeks(endingAt: Fixtures.day(1, hour: 1), count: 2, sessions: data.practiceSessions, library: library,
                                        calendar: calendar)
        XCTAssertEqual(weeks.last?.start, Workload.startOfWeek(for: Fixtures.day(1, hour: 1), calendar: calendar))
        XCTAssertEqual(weeks.map(\.totals.shots), [0, 170])

        XCTAssertEqual(PracticeStats.streak(data.practiceSessions, today: Fixtures.day(1, hour: 8), calendar: calendar), 2)
        XCTAssertEqual(PracticeStats.streak(data.practiceSessions, today: Fixtures.day(2, hour: 1), calendar: calendar), 2,
                       "yesterday's run counts until today is over")
        XCTAssertEqual(PracticeStats.streak(data.practiceSessions, today: Fixtures.day(3, hour: 1), calendar: calendar), 0)
        XCTAssertEqual(PracticeStats.bestShotDay(data.practiceSessions, library: library, calendar: calendar)?.totals.shots, 120)
    }

    func testBackhandMixAndPace() {
        func drills(_ wrist: Int, _ backhand: Int) -> [String: PracticeTotals] {
            ["wrist-shot": PracticeTotals(shots: wrist), "backhand": PracticeTotals(shots: backhand)]
        }
        XCTAssertEqual(try XCTUnwrap(PracticeStats.backhandShare(drills(90, 10))), 0.1, accuracy: 0.0001)
        XCTAssertTrue(PracticeStats.backhandBehind(drills(90, 10)))
        XCTAssertFalse(PracticeStats.backhandBehind(drills(80, 20)))
        XCTAssertFalse(PracticeStats.backhandBehind(drills(40, 0)), "too few shots to judge")
        XCTAssertNil(PracticeStats.backhandShare([:]))

        let monday = Workload.startOfWeek(for: Fixtures.day(0, hour: 1), calendar: calendar)
        let wednesday = calendar.date(byAdding: .hour, value: 2 * 24 + 18, to: monday)!
        XCTAssertEqual(try XCTUnwrap(PracticeStats.pace(300, now: wednesday, calendar: calendar)), 700, accuracy: 0.0001,
                       "300 in three days is 700 by Sunday")
        XCTAssertNil(PracticeStats.pace(0, now: wednesday, calendar: calendar))
    }

    func testChallengeBests() {
        var data = hockey()
        data.practiceSessions.append(PracticeSession(date: Fixtures.day(2, hour: 5), sets: [PracticeSet(drillID: "quick-hands", amount: 85)],
                                                     challengeSeconds: 30))
        data.practiceSessions.append(PracticeSession(date: Fixtures.day(3, hour: 5), sets: [PracticeSet(drillID: "quick-hands", amount: 120)],
                                                     challengeSeconds: 60))
        XCTAssertEqual(PracticeStats.challengeLengths(data.practiceSessions), [30, 60])
        let best = try? XCTUnwrap(PracticeStats.challengeBests(data.practiceSessions, seconds: 30)["quick-hands"])
        XCTAssertEqual(best?.reps, 85)
        XCTAssertEqual(best?.date, Fixtures.day(1, hour: 6), "the earliest wins a tie")
    }

    func testDraft() {
        let wrist = PracticeCatalog.builtIn(id: "wrist-shot")!, backhand = PracticeCatalog.builtIn(id: "backhand")!
        let hands = PracticeCatalog.builtIn(id: "quick-hands")!
        var draft = PracticeDraft()
        draft.pick(wrist)
        XCTAssertEqual(draft.amount("wrist-shot"), 50, "picked with its default")
        draft.pickAll([backhand, hands])
        draft.setAll(40, in: [wrist, backhand])
        XCTAssertEqual(draft.amount("backhand"), 40)
        XCTAssertEqual(draft.amount("quick-hands"), 3, "only the drills given change")
        draft.setOnTarget(60, drillID: "wrist-shot")
        XCTAssertEqual(draft.onTarget("wrist-shot"), 40, "no more on target than shots")
        draft.set(30, drillID: "wrist-shot")
        XCTAssertEqual(draft.onTarget("wrist-shot"), 30)
        draft.setOnTarget(5, drillID: "quick-hands")
        XCTAssertEqual(draft.sets(in: [wrist, backhand, hands]), [
            PracticeSet(drillID: "wrist-shot", amount: 30, onTarget: 30),
            PracticeSet(drillID: "backhand", amount: 40),
            PracticeSet(drillID: "quick-hands", amount: 3)
        ], "on target only for drills that count it")
        XCTAssertEqual(draft.totals(in: [wrist, backhand, hands]).shots, 70)
        draft.unpick("wrist-shot")
        XCTAssertNil(draft.onTarget("wrist-shot"))
        XCTAssertEqual(PracticeDraft(sets: [PracticeSet(drillID: "backhand", amount: 10, onTarget: 4)]).onTarget("backhand"), 4)
    }

    func testShotsAndStickhandlingTasks() {
        var data = hockey()
        let roster = UUID()
        let weekStart = DayKey(Workload.startOfWeek(for: Fixtures.day(0, hour: 1), calendar: calendar), calendar: calendar)
        let shots = Assignment(rosterID: roster, kind: .shots, title: "Shots", schedule: .weekly, startsOn: weekStart, targetReps: 1000)
        let hands = Assignment(rosterID: roster, kind: .stickhandling, title: "Hands", schedule: .weekly, startsOn: weekStart, targetMinutes: 15)
        data.assignments = [shots, hands]
        let now = Fixtures.day(1, hour: 8)
        let shotStatus = try? XCTUnwrap(data.assignmentStatus(shots, now: now, calendar: calendar))
        XCTAssertEqual(shotStatus?.logged, 170)
        XCTAssertEqual(shotStatus?.progressText, "170 / 1,000 shots")
        XCTAssertEqual(shots.summary(calendar: calendar), "1,000 shots every week")
        let handStatus = try? XCTUnwrap(data.assignmentStatus(hands, now: now, calendar: calendar))
        XCTAssertEqual(handStatus?.logged, 16)
        XCTAssertEqual(handStatus?.isDone, true)
        XCTAssertEqual(hands.summary(calendar: calendar), "15 min of stickhandling every week")

        let row = AssignmentRow(Assignment(rosterID: roster, kind: .stickhandling, title: "Hands", schedule: .daily, startsOn: weekStart,
                                           targetReps: 50, targetMinutes: 20))
        XCTAssertNil(row.targetReps)
        XCTAssertEqual(row.targetMinutes, 20)
        XCTAssertEqual(AssignmentRow(shots).targetReps, 1000)
    }

    func testCoachWeekShowsPractice() {
        var data = hockey()
        data.practiceSessions.append(PracticeSession(date: Fixtures.day(2, hour: 5), sets: [PracticeSet(drillID: "wrist-shot", amount: 200)]))
        let week = CoachWeek(data, now: Fixtures.day(2, hour: 8), calendar: calendar)
        XCTAssertEqual(week.practice.shots, 370)
        XCTAssertEqual(week.stickhandlingMinutes, 16)
        XCTAssertEqual(week.practiceStreak, 3)
        XCTAssertTrue(week.flags.contains(.backhandBehind), "20 backhands out of 370 shots")
        XCTAssertEqual(CoachWeek.Flag.backhandBehind.title, "Backhand behind")
    }

    func testPracticeRoundTripsThroughTheCloud() throws {
        var data = hockey()
        data.profile.weeklyShotGoal = 1500
        data.profile.weeklyStickhandlingGoal = 0
        data.practiceDrills = [PracticeDrill(id: "tarp-corners", name: "  ", kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 900)]
        let rows = ProfileSnapshot(data)
        XCTAssertEqual(rows.profile.weeklyShotGoal, 1500)
        XCTAssertEqual(rows.practiceDrills.first?.name, "Drill", "a blank name isn't stored")
        XCTAssertEqual(rows.practiceDrills.first?.defaultAmount, 500)
        XCTAssertEqual(rows.practiceSessions.first?.sets.map(\.onTarget), [60, nil, nil])

        let back = rows.appData
        XCTAssertEqual(back.practiceSessions, data.practiceSessions)
        XCTAssertEqual(back.profile.weeklyShotGoal, 1500)
        XCTAssertEqual(back.profile.weeklyStickhandlingGoal, 0)

        // A sync record from before hockey practice has none of it.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(rows)) as? [String: Any])
        object["practiceDrills"] = nil
        object["practiceSessions"] = nil
        let old = try AppData.decoder.decode(ProfileSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.practiceSessions.isEmpty && old.practiceDrills.isEmpty)
    }

    func testMergeSendsPracticeAndRespectsAccess() {
        let data = hockey()
        let base = ProfileSnapshot(data)
        var local = data
        local.practiceSessions[0].sets[0].amount = 120
        local.practiceSessions.remove(at: 2)
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(outcome.changes.practiceSessions.upserts.map(\.id), [data.practiceSessions[0].id])
        XCTAssertEqual(outcome.changes.practiceSessions.deletes, [data.practiceSessions[2].id])

        // A coach on the athlete can read training but not write it, so nothing of theirs is sent.
        var remote = base
        remote.access = ProfileAccess(role: .viewer, relationships: [.coach])
        let coach = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: remote)
        XCTAssertTrue(coach.changes.practiceSessions.isEmpty)
        XCTAssertEqual(coach.merged.practiceSessions, base.practiceSessions, "the cloud's copy wins")
    }

    func testFilesSavedBeforePracticeAndBlankSeason() throws {
        let data = hockey()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(data)) as? [String: Any])
        object["practiceDrills"] = nil
        object["practiceSessions"] = nil
        var profile = try XCTUnwrap(object["profile"] as? [String: Any])
        profile["weeklyShotGoal"] = nil
        profile["weeklyStickhandlingGoal"] = nil
        object["profile"] = profile
        let old = try AppData.decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.practiceSessions.isEmpty)
        XCTAssertEqual(old.profile.weeklyShotGoal, 1000)
        XCTAssertEqual(old.profile.weeklyStickhandlingGoal, 60)

        var withDrill = data
        withDrill.practiceDrills = [PracticeDrill(name: "Tarp corners", kind: .shooting, measure: .shots, defaultAmount: 40)]
        let blank = withDrill.blankSeason()
        XCTAssertTrue(blank.practiceSessions.isEmpty)
        XCTAssertEqual(blank.practiceDrills.count, 1, "the athlete's drills stay")
        XCTAssertEqual(blank.practiceLibrary.count, 18)
    }
}
