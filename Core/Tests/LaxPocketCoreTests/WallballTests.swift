import XCTest
@testable import LaxPocketCore

final class WallballLibraryTests: XCTestCase {
    func testCatalogHasUniqueIDsAndBothHandModes() {
        let ids = WallballCatalog.drills.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(WallballCatalog.drills.contains { $0.hands == .each })
        XCTAssertTrue(WallballCatalog.drills.contains { $0.hands == .together })
        XCTAssertTrue(WallballCatalog.drills.allSatisfy { WallballDrill.defaultRepsRange.contains($0.defaultReps) && !$0.isHidden })
    }

    func testLibraryAppliesChangesThenAddsTheAthletesDrills() {
        let mine = WallballDrill(id: "mine", name: "Twister")
        var overhand = WallballCatalog.drills[0]
        overhand.defaultReps = 100
        let library = WallballCatalog.library([mine, overhand])
        XCTAssertEqual(library.count, WallballCatalog.drills.count + 1)
        XCTAssertEqual(library.first?.defaultReps, 100, "a changed built-in keeps its place in the routine")
        XCTAssertEqual(library.last, mine)
        XCTAssertTrue(overhand.isBuiltIn)
        XCTAssertFalse(mine.isBuiltIn)
    }

    func testFindsDrillsByID() {
        let data = Fixtures.season()
        XCTAssertEqual(data.wallballDrill(id: "twister")?.name, "Twister")
        XCTAssertEqual(data.wallballDrill(id: "behind-the-back")?.isHidden, true, "the athlete's change wins over the built-in")
        XCTAssertEqual(data.wallballDrill(id: "overhand")?.name, "Overhand")
        XCTAssertNil(data.wallballDrill(id: "gone"))
    }
}

final class WallballSessionTests: XCTestCase {
    func testNormalizesSets() {
        let sets = WallballSession.normalized([
            WallballSet(drillID: "a", hand: .right, reps: 10), WallballSet(drillID: "b", hand: .both, reps: 0),
            WallballSet(drillID: "a", hand: .left, reps: 5), WallballSet(drillID: "a", hand: .right, reps: 15)
        ])
        XCTAssertEqual(sets, [WallballSet(drillID: "a", hand: .right, reps: 25), WallballSet(drillID: "a", hand: .left, reps: 5)])
    }

    func testCountsRepsByHand() {
        let session = Fixtures.season().wallballSessions[0]
        XCTAssertEqual(session.reps, HandReps(right: 50, left: 55, both: 30))
        XCTAssertEqual(session.reps.total, 135)
        XCTAssertEqual(session.drillCount, 3)
        XCTAssertFalse(session.isChallenge)
        XCTAssertEqual(session.reps.leftShare ?? 0, 55.0 / 105.0, accuracy: 1e-9)
        XCTAssertNil(HandReps(both: 10).leftShare)
    }
}

final class WallballStatsTests: XCTestCase {
    private let calendar = Calendar.laxWeek

    /// Fixture days at an hour that falls on the same calendar day from UTC−12 to UTC+2.
    private func at(_ day: Int, hour: Int = 7) -> Date { Fixtures.day(day, hour: hour) }

    private func session(_ day: Int, hour: Int = 7, _ sets: [WallballSet], challenge: Int? = nil) -> WallballSession {
        WallballSession(date: Fixtures.day(day, hour: hour), sets: sets, challengeSeconds: challenge)
    }

    private func reps(_ count: Int, _ drill: String = "overhand", _ hand: WallballHand = .right) -> WallballSet {
        WallballSet(drillID: drill, hand: hand, reps: count)
    }

    func testDailyTotalsIncludeDaysOff() {
        let sessions = [session(0, [reps(50)]), session(0, hour: 8, [reps(20, "overhand", .left)]), session(2, [reps(10)])]
        let days = WallballStats.days(endingOn: at(3), count: 5, sessions: sessions, calendar: calendar)
        XCTAssertEqual(days.count, 5)
        XCTAssertEqual(days.map(\.reps.total), [0, 70, 0, 10, 0])
        XCTAssertEqual(days[1].reps, HandReps(right: 50, left: 20))
        XCTAssertEqual(days.last?.start, calendar.startOfDay(for: at(3)))
    }

    func testWeeklyTotals() {
        let sessions = [session(0, [reps(50)]), session(-7, [reps(30)]), session(-30, [reps(99)])]
        let weeks = WallballStats.weeks(endingAt: at(0), count: 3, sessions: sessions, calendar: calendar)
        XCTAssertEqual(weeks.map(\.reps.total), [0, 30, 50])
        XCTAssertEqual(weeks.last?.start, Workload.startOfWeek(for: at(0), calendar: calendar))
    }

    func testStreakCountsDaysInARow() {
        let sessions = [session(0, [reps(5)]), session(-1, [reps(5)]), session(-2, [reps(5)]), session(-4, [reps(5)])]
        XCTAssertEqual(WallballStats.streak(sessions, today: at(0), calendar: calendar), 3)
        XCTAssertEqual(WallballStats.streak(sessions, today: at(1), calendar: calendar), 3, "still alive until a whole day is missed")
        XCTAssertEqual(WallballStats.streak(sessions, today: at(2), calendar: calendar), 0)
        XCTAssertEqual(WallballStats.streak([], today: at(0), calendar: calendar), 0)
    }

    func testBestDayAndByDrill() {
        let sessions = [session(0, [reps(50), reps(10, "sidearm", .left)]), session(1, [reps(80)]), session(2, [reps(60)])]
        XCTAssertEqual(WallballStats.bestDay(sessions, calendar: calendar)?.reps.total, 80)
        XCTAssertNil(WallballStats.bestDay([], calendar: calendar))
        let byDrill = WallballStats.byDrill(sessions)
        XCTAssertEqual(byDrill["overhand"], HandReps(right: 190))
        XCTAssertEqual(byDrill["sidearm"], HandReps(left: 10))
    }

    func testFlagsTheLaggingHand() {
        XCTAssertEqual(WallballStats.laggingHand(HandReps(right: 70, left: 30)), .left)
        XCTAssertEqual(WallballStats.laggingHand(HandReps(right: 30, left: 70)), .right)
        XCTAssertNil(WallballStats.laggingHand(HandReps(right: 55, left: 45)))
        XCTAssertNil(WallballStats.laggingHand(HandReps(right: 9, left: 1)), "too few reps to call it")
        XCTAssertNil(WallballStats.laggingHand(HandReps(both: 100)))
    }

    func testChallengeBestsPerLength() {
        let sessions = [
            session(0, [reps(40, "quick-sticks", .right), reps(30, "quick-sticks", .left)], challenge: 30),
            session(1, [reps(45, "quick-sticks", .right), reps(30, "quick-sticks", .left)], challenge: 30),
            session(2, [reps(90, "quick-sticks", .right)], challenge: 60),
            session(3, [reps(500, "quick-sticks", .right)])
        ]
        XCTAssertEqual(WallballStats.challengeLengths(sessions), [30, 60])
        let bests = WallballStats.challengeBests(sessions, seconds: 30)
        XCTAssertEqual(bests[DrillHand(drillID: "quick-sticks", hand: .right)]?.reps, 45)
        XCTAssertEqual(bests[DrillHand(drillID: "quick-sticks", hand: .left)]?.sessionID, sessions[0].id, "the first to reach a best keeps it")
        XCTAssertEqual(WallballStats.challengeBests(sessions, seconds: 60).count, 1)
    }
}

final class WallballDraftTests: XCTestCase {
    private let overhand = WallballDrill(id: "overhand", name: "Overhand", defaultReps: 50)
    private let sidearm = WallballDrill(id: "sidearm", name: "Sidearm")
    private let switchHands = WallballDrill(id: "switch", name: "Catch and switch", hands: .together, defaultReps: 30)
    private var drills: [WallballDrill] { [overhand, sidearm, switchHands] }

    func testPickAllUsesEachDrillsDefault() {
        var draft = WallballDraft()
        draft.pickAll(drills)
        XCTAssertEqual(draft.pickedCount, 3)
        XCTAssertEqual(draft.sets(in: drills), [
            WallballSet(drillID: "overhand", hand: .right, reps: 50), WallballSet(drillID: "overhand", hand: .left, reps: 50),
            WallballSet(drillID: "sidearm", hand: .right, reps: 25), WallballSet(drillID: "sidearm", hand: .left, reps: 25),
            WallballSet(drillID: "switch", hand: .both, reps: 30)
        ])
    }

    func testSetAllThenCustomize() {
        var draft = WallballDraft()
        draft.pickAll(drills)
        draft.setAll(20)
        XCTAssertEqual(draft.total(in: drills), HandReps(right: 40, left: 40, both: 20))
        draft.set(35, drillID: "sidearm", hand: .left)
        draft.set(0, drillID: "overhand", hand: .right)
        draft.unpick("switch")
        XCTAssertEqual(draft.sets(in: drills), [
            WallballSet(drillID: "overhand", hand: .left, reps: 20),
            WallballSet(drillID: "sidearm", hand: .right, reps: 20), WallballSet(drillID: "sidearm", hand: .left, reps: 35)
        ], "a hand at 0 is skipped")
        draft.set(10, drillID: "switch", hand: .both)
        XCTAssertFalse(draft.isPicked("switch"), "setting reps doesn't pick a drill")
    }

    func testPickAllKeepsCustomizedDrills() {
        var draft = WallballDraft()
        draft.pick(sidearm, reps: 12)
        draft.pickAll(drills, reps: 40)
        XCTAssertEqual(draft.reps("sidearm", .right), 12)
        XCTAssertEqual(draft.reps("overhand", .left), 40)
        XCTAssertEqual(draft.reps("switch", .both), 40)
        draft.toggle(sidearm)
        XCTAssertFalse(draft.isPicked("sidearm"))
        draft.clear()
        XCTAssertTrue(draft.isEmpty)
    }

    func testRepsAreClamped() {
        var draft = WallballDraft()
        draft.pick(overhand, reps: -5)
        XCTAssertEqual(draft.reps("overhand", .right), 0)
        draft.setAll(99_999)
        XCTAssertEqual(draft.reps("overhand", .left), WallballSet.repsRange.upperBound)
    }

    func testRoundTripsASession() {
        let session = Fixtures.season().wallballSessions[0]
        let library = Fixtures.season().wallballLibrary
        let draft = WallballDraft(sets: session.sets)
        XCTAssertEqual(draft.total(in: library), session.reps)
        XCTAssertEqual(Set(draft.sets(in: library)), Set(session.sets))
        XCTAssertEqual(draft.sets(in: []).count, session.sets.count, "drills missing from the library are kept")
    }
}

final class WallballChallengeTests: XCTestCase {
    func testRoundsFollowDrillsAndHands() {
        let drills = [WallballDrill(id: "a", name: "A"), WallballDrill(id: "b", name: "B", hands: .together)]
        XCTAssertEqual(WallballChallenge.rounds(drills, hands: .rightAndLeft), [
            DrillHand(drillID: "a", hand: .right), DrillHand(drillID: "a", hand: .left), DrillHand(drillID: "b", hand: .both)
        ])
        XCTAssertEqual(WallballChallenge.rounds(drills, hands: .left), [DrillHand(drillID: "a", hand: .left), DrillHand(drillID: "b", hand: .both)])
        XCTAssertTrue(WallballChallenge.rounds([], hands: .right).isEmpty)
    }

    func testLengthText() {
        XCTAssertEqual(WallballChallenge.lengthText(30), "30 sec")
        XCTAssertEqual(WallballChallenge.lengthText(60), "1 min")
        XCTAssertEqual(WallballChallenge.lengthText(90), "1 min 30 sec")
        XCTAssertTrue(WallballChallenge.lengths.allSatisfy(WallballChallenge.secondsRange.contains))
    }
}
