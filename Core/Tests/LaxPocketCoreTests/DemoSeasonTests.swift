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
}
