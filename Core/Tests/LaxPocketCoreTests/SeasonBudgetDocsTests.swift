import XCTest
@testable import LaxPocketCore

final class SeasonTests: XCTestCase {
    func testRecordAndTotals() {
        let now = Date()
        let events = [
            SeasonEvent(kind: .game, title: "A", team: "T", date: now, ourScore: 11, theirScore: 7, stats: GameStats(goals: 2, assists: 1, shots: 5, groundBalls: 4, drawControls: 3)),
            SeasonEvent(kind: .game, title: "B", team: "T", date: now, ourScore: 6, theirScore: 8, stats: GameStats(goals: 1, groundBalls: 3, drawControls: 4)),
            SeasonEvent(kind: .game, title: "C", team: "T", date: now, ourScore: 5, theirScore: 5),
            SeasonEvent(kind: .showcase, title: "D", team: "T", date: now.addingTimeInterval(86_400))
        ]
        let record = Season.record(for: events)
        XCTAssertEqual(record.line, "1–1–1")
        XCTAssertEqual(record.gamesPlayed, 3)
        XCTAssertEqual(record.totals.goals, 3)
        XCTAssertEqual(record.totals.drawControls, 7)
        XCTAssertEqual(events[0].stats?.summaryLine, "2G · 1A · 4GB · 3DC")
        XCTAssertEqual(try XCTUnwrap(events[0].stats?.shootingPercentage), 0.4, accuracy: 1e-9)
        XCTAssertEqual(Season.upcoming(events, from: now).map(\.title), ["D"])
        XCTAssertEqual(Season.results(events).count, 3)
    }
}

final class BudgetTests: XCTestCase {
    func testSummary() {
        let now = Date()
        let expenses = [
            Expense(date: now, title: "Club", category: .teamFees, amount: 3000),
            Expense(date: now, title: "Coach", category: .coaching, amount: 1000),
            Expense(date: now, title: "Coach 2", category: .coaching, amount: 500),
            Expense(date: now, title: "Stick", category: .equipment, amount: 500)
        ]
        let summary = BudgetMath.summary(expenses: expenses, budget: 10_000)
        XCTAssertEqual(summary.spent, 5000, accuracy: 1e-9)
        XCTAssertEqual(summary.remaining, 5000, accuracy: 1e-9)
        XCTAssertEqual(summary.fractionUsed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(summary.byCategory.first?.category, .teamFees)
        XCTAssertEqual(summary.byCategory.first?.relativeToLargest ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(summary.byCategory.first { $0.category == .coaching }?.share ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertFalse(summary.isOverBudget)
        XCTAssertTrue(BudgetMath.summary(expenses: expenses, budget: 4000).isOverBudget)
    }
}

final class MentalDocTests: XCTestCase {
    func testKindInference() {
        XCTAssertEqual(DocKind.infer(from: URL(string: "https://docs.google.com/document/d/abc/edit?usp=sharing&ouid=1&rtpof=true&sd=true")!), .word)
        XCTAssertEqual(DocKind.infer(from: URL(string: "https://docs.google.com/document/d/abc/edit")!), .googleDoc)
        XCTAssertEqual(DocKind.infer(from: URL(string: "https://example.com/plan.pdf")!), .pdf)
        XCTAssertEqual(DocKind.infer(from: URL(string: "https://drive.google.com/file/d/abc/view")!), .link)
    }

    func testURLNormalizing() {
        XCTAssertEqual(MentalDoc.normalizedURL(from: "  docs.google.com/document/d/abc  ")?.absoluteString, "https://docs.google.com/document/d/abc")
        XCTAssertNil(MentalDoc.normalizedURL(from: ""))
        XCTAssertNil(MentalDoc.normalizedURL(from: "not a link"))
    }
}

final class ThemeTests: XCTestCase {
    func testCatalogHasOriginalPlusTopTen() {
        XCTAssertEqual(ThemeCatalog.all.count, 11)
        XCTAssertEqual(ThemeCatalog.all.compactMap(\.rank), Array(1...10))
        XCTAssertEqual(Set(ThemeCatalog.all.map(\.id)).count, 11)
        XCTAssertEqual(ThemeCatalog.palette(id: "nope").id, ThemeCatalog.defaultID)
    }

    /// White text sits on the primary colour (buttons, headers) and accent text sits on white and on its tint.
    func testTextContrastMeetsWCAG_AA() throws {
        for theme in ThemeCatalog.all {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorMath.contrast("#FFFFFF", theme.primary)), 4.5, "\(theme.name) white on primary")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorMath.contrast(theme.onPrimary, theme.primary)), 4.5, "\(theme.name) onPrimary")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorMath.contrast(theme.accentText, "#FFFFFF")), 4.5, "\(theme.name) accentText on white")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorMath.contrast(theme.accentText, theme.accentTint)), 4.5, "\(theme.name) accentText on tint")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(ColorMath.contrast(theme.primary, theme.primaryTint)), 4.5, "\(theme.name) primary on tint")
        }
    }
}

final class AppDataTests: XCTestCase {
    func testSampleDataRoundTripsThroughJSON() throws {
        let data = SampleData.make()
        XCTAssertTrue(data.isSample)
        XCTAssertFalse(data.sessions.isEmpty)
        XCTAssertTrue(data.sessions.allSatisfy { $0.date <= Date() })
        let json = try AppData.encoder.encode(data)
        let decoded = try AppData.decoder.decode(AppData.self, from: json)
        XCTAssertEqual(decoded.sessions.count, data.sessions.count)
        XCTAssertEqual(decoded.profile, data.profile)
        XCTAssertEqual(decoded.events.map(\.title), data.events.map(\.title))
    }

    func testBlankSeasonKeepsProgramsOnly() {
        let blank = SampleData.make().blankSeason()
        XCTAssertFalse(blank.isSample)
        XCTAssertTrue(blank.sessions.isEmpty)
        XCTAssertTrue(blank.events.isEmpty)
        XCTAssertFalse(blank.programs.isEmpty)
    }

    func testSeasonTitle() {
        var profile = SampleData.make().profile
        profile.firstName = "Sam"
        XCTAssertEqual(profile.seasonTitle, "Sam’s Season")
        profile.firstName = " "
        XCTAssertEqual(profile.seasonTitle, "My Season")
    }
}
