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
        XCTAssertTrue(Season.past(events, from: now).isEmpty)
    }

    func testPastEventsWithoutAResult() {
        let now = Date()
        let events = [
            SeasonEvent(kind: .game, title: "Scored", team: "T", date: now.addingTimeInterval(-86_400), ourScore: 3, theirScore: 2),
            SeasonEvent(kind: .game, title: "Needs score", team: "T", date: now.addingTimeInterval(-86_400)),
            SeasonEvent(kind: .camp, title: "Camp", team: "T", date: now.addingTimeInterval(-3 * 86_400), endDate: now.addingTimeInterval(-2 * 86_400)),
            SeasonEvent(kind: .tournament, title: "Still on", team: "T", date: now.addingTimeInterval(-86_400), endDate: now.addingTimeInterval(86_400))
        ]
        XCTAssertEqual(Season.past(events, from: now).map(\.title), ["Needs score", "Camp"])
        XCTAssertEqual(Season.upcoming(events, from: now).map(\.title), ["Still on"])
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

    func testSeasonByProgram() {
        var data = Fixtures.season()
        data.expenses.append(Expense(date: Fixtures.day(5), title: "Next year's deposit", category: .teamFees, amount: 500,
                                     programID: "club", season: 2027))
        let summary = BudgetMath.season(2026, in: data)
        XCTAssertEqual(summary.overall, 14_000)
        XCTAssertEqual(summary.allocated, 4200)
        XCTAssertEqual(summary.summary.budget, 14_000)
        XCTAssertEqual(summary.summary.spent, 2170.5, accuracy: 1e-9, "only this season's expenses")
        XCTAssertFalse(summary.isOverAllocated)
        XCTAssertEqual(summary.programs.map(\.id), ["club", "skills-coach", ""], "program order, then spending with no program")
        XCTAssertEqual(summary.programs[0].spent, 1850)
        XCTAssertEqual(summary.programs[0].budget, 3000)
        XCTAssertEqual(summary.programs[1].spent, 0)
        XCTAssertEqual(summary.programs[2].spent, 320.5)
        XCTAssertEqual(summary.programs[2].expenseCount, 1)

        let next = BudgetMath.season(2027, in: data)
        XCTAssertEqual(next.overall, 0)
        XCTAssertEqual(next.summary.budget, 3200, "with no overall budget, the program budgets add up to the budget")
        XCTAssertEqual(next.programs.map(\.id), ["club"])
        XCTAssertEqual(next.programs[0].spent, 500)

        data.setBudget(4000, for: 2026)
        XCTAssertTrue(BudgetMath.season(2026, in: data).isOverAllocated)
    }

    func testSettingBudgets() {
        var data = Fixtures.season()
        XCTAssertEqual(data.seasonBudget, 14_000, "the season the profile is set to")
        XCTAssertEqual(data.seasonBudgets, [SeasonBudget(season: 2026, amount: 14_000)])
        data.setBudget(9000, for: 2027)
        data.seasonBudget = 15_000
        XCTAssertEqual(data.seasonBudgets.map(\.amount), [15_000, 9000])
        data.setBudget(0, for: 2027)
        XCTAssertEqual(data.seasonBudgets.map(\.season), [2026], "0 removes a budget")

        data.setProgramBudget(3500, programID: "club", season: 2026)
        XCTAssertEqual(data.programBudget("club", season: 2026), 3500)
        XCTAssertEqual(data.programBudget("club", season: 2027), 3200)
        data.setProgramBudget(0, programID: "skills-coach", season: 2026)
        XCTAssertEqual(data.programBudgets.map(\.programID), ["club", "club"])
    }

    func testProgramSeasons() {
        let data = Fixtures.season()
        let club = data.programs[0]
        XCTAssertTrue(club.runs(in: 2026))
        XCTAssertTrue(club.runs(in: 2028))
        XCTAssertFalse(club.runs(in: 2029))
        XCTAssertEqual(club.seasonsText, "2026/27 – 2028/29")
        XCTAssertEqual(data.programs(in: 2029).map(\.id), ["skills-coach", "gym", "combine"], "open-ended programs run every season")
        XCTAssertEqual(Program(id: "x", name: "X", detail: "", group: .showcases, sessionCategory: nil, monogram: "X", firstSeason: 2027).seasonsText,
                       "From 2027/28")
        XCTAssertEqual(data.budgetSeasons(current: 2026), [2028, 2027, 2026])
    }

    func testSeasonLabels() {
        XCTAssertEqual(AthleteProfile.seasonStart(label: "2026/27"), 2026)
        XCTAssertEqual(AthleteProfile.seasonStart(label: " 2026-2027"), 2026)
        XCTAssertNil(AthleteProfile.seasonStart(label: "Fall"))
        XCTAssertNil(AthleteProfile.seasonStart(label: "26/27"))
        XCTAssertEqual(AthleteProfile.seasonLabel(start: 2026), "2026/27")
        XCTAssertEqual(Fixtures.season().profile.currentSeason(), 2026)
    }

    /// Expenses saved before seasons count toward the season of their date.
    func testOldExpensesGetTheSeasonOfTheirDate() throws {
        let json = #"[{"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "date": "2027-03-01T12:00:00Z", "title": "Stick", "category": "equipment", "amount": 250, "note": ""}]"#
        let expense = try XCTUnwrap(AppData.decoder.decode([Expense].self, from: Data(json.utf8)).first)
        XCTAssertEqual(expense.season, 2026)
        XCTAssertNil(expense.programID)
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
    func testRoundTripsThroughJSON() throws {
        let data = Fixtures.season()
        let json = try AppData.encoder.encode(data)
        let decoded = try AppData.decoder.decode(AppData.self, from: json)
        XCTAssertEqual(decoded.id, data.id)
        XCTAssertEqual(decoded.sessions.count, data.sessions.count)
        XCTAssertEqual(decoded.profile, data.profile)
        XCTAssertEqual(decoded.events.map(\.title), data.events.map(\.title))
        XCTAssertEqual(decoded.themeID, "northwestern")
    }

    /// Version 1 files had no profile ID and carried an `isSample` flag.
    func testReadsVersion1Files() throws {
        let json = """
        {"schemaVersion": 1, "isSample": false, "seasonBudget": 500, "themeID": "navy",
         "profile": {"firstName": "Sam", "classYear": 2031, "positions": "Attack", "benchmarkGroup": "u15Women",
                     "mentalCoachName": "", "weeklyGoalHours": 10, "season": "2026/27"},
         "programs": [], "sessions": [], "events": [], "expenses": [], "docs": [],
         "combineResults": [{"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "date": "2026-09-01T10:00:00Z", "event": "Baseline",
                             "measurements": [{"metric": "gripLeft", "value": 262}], "heightText": "", "weightText": "", "isSample": true}]}
        """
        let data = try AppData.decoder.decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(data.schemaVersion, AppData.currentSchemaVersion)
        XCTAssertEqual(data.profile.firstName, "Sam")
        XCTAssertEqual(data.seasonBudget, 500)
        XCTAssertEqual(data.seasonBudgets, [SeasonBudget(season: 2026, amount: 500)], "the old budget is for the season the profile was set to")
        XCTAssertEqual(data.themeID, "navy")
        XCTAssertEqual(data.combineResults.first?.value(for: .gripLeft), 262)
        XCTAssertTrue(data.bodyMeasurements.isEmpty)
        XCTAssertEqual(data.profile.bodyUnits, .imperial)
        XCTAssertTrue(data.wallballDrills.isEmpty)
        XCTAssertTrue(data.wallballSessions.isEmpty)
    }

    func testBlankSeasonKeepsProfileAndPrograms() {
        let season = Fixtures.season()
        let blank = season.blankSeason()
        XCTAssertEqual(blank.id, season.id)
        XCTAssertEqual(blank.profile, season.profile)
        XCTAssertEqual(blank.programs, season.programs)
        XCTAssertEqual(blank.seasonBudgets, season.seasonBudgets)
        XCTAssertEqual(blank.programBudgets, season.programBudgets)
        XCTAssertEqual(blank.expenses, season.expenses, "expenses belong to a season, so they're kept")
        XCTAssertTrue(blank.sessions.isEmpty)
        XCTAssertTrue(blank.events.isEmpty)
        XCTAssertTrue(blank.docs.isEmpty)
        XCTAssertTrue(blank.combineResults.isEmpty)
        XCTAssertEqual(blank.bodyMeasurements, season.bodyMeasurements, "height and weight history belongs to the athlete, not the season")
        XCTAssertEqual(blank.wallballDrills, season.wallballDrills, "drills are kept like programs")
        XCTAssertTrue(blank.wallballSessions.isEmpty)
    }

    func testNewProfileStartsEmpty() {
        let profile = AthleteProfile(firstName: "Sam", classYear: 2031, positions: "", benchmarkGroup: .u15Women, season: "2026/27")
        let data = AppData.newProfile(profile, themeID: "navy")
        XCTAssertTrue(data.programs.isEmpty)
        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertEqual(data.summary, ProfileSummary(id: data.id, name: "Sam", themeID: "navy"))
    }

    func testSeasonTitle() {
        var profile = Fixtures.season().profile
        profile.firstName = "Sam"
        XCTAssertEqual(profile.seasonTitle, "Sam’s Season")
        profile.firstName = " "
        XCTAssertEqual(profile.seasonTitle, "My Season")
    }

    func testSeasonLabelTurnsOverInAugust() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        func date(_ y: Int, _ m: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: 15))! }
        XCTAssertEqual(AthleteProfile.seasonLabel(for: date(2026, 9), calendar: calendar), "2026/27")
        XCTAssertEqual(AthleteProfile.seasonLabel(for: date(2027, 3), calendar: calendar), "2026/27")
        XCTAssertEqual(AthleteProfile.seasonLabel(for: date(2027, 8), calendar: calendar), "2027/28")
        XCTAssertEqual(AthleteProfile.seasonLabel(for: date(2099, 12), calendar: calendar), "2099/00")
    }

    func testProgramMonograms() {
        XCTAssertEqual(Program.suggestedMonogram(for: "Team Ontario U15"), "TOU")
        XCTAssertEqual(Program.suggestedMonogram(for: "Rockstar 2031"), "R31")
        XCTAssertEqual(Program.suggestedMonogram(for: "The Quarry Fitness Training"), "TQF")
        XCTAssertEqual(Program.suggestedMonogram(for: "OAA"), "OAA")
        XCTAssertEqual(Program.suggestedMonogram(for: "DodgeCity"), "DC")
        XCTAssertEqual(Program.suggestedMonogram(for: "quarry"), "Q")
        XCTAssertEqual(Program.suggestedMonogram(for: "  "), "?")
        XCTAssertEqual(Program.defaultCategory(for: .skills), .skills)
        XCTAssertNil(Program.defaultCategory(for: .showcases))
        XCTAssertEqual(Program.defaultCategory(for: .mental), .mental)
        XCTAssertNotEqual(Program.newID(), Program.newID())
    }

    func testMentalProgramsSavedWithoutACategoryLogAsMental() {
        let old = Program(id: "mc", name: "Mental coach", detail: "", group: .mental, sessionCategory: nil, monogram: "MC")
        XCTAssertEqual(old.loggedCategory, .mental)
        let showcase = Program(id: "s", name: "Showcase", detail: "", group: .showcases, sessionCategory: nil, monogram: "S")
        XCTAssertNil(showcase.loggedCategory)
        let club = Program(id: "c", name: "Club", detail: "", group: .teams, sessionCategory: .team, monogram: "C")
        XCTAssertEqual(club.loggedCategory, .team)
    }

    func testMentalSessionsOfferMentalFocusTags() {
        XCTAssertTrue(TrainingSession.focusOptions(for: .mental).contains("Game plan"))
        XCTAssertTrue(TrainingSession.focusOptions(for: .mental).contains("Pre-game routine"))
        XCTAssertEqual(TrainingSession.focusOptions(for: .skills), TrainingSession.focusOptions)
    }

    func testSessionCountByProgram() {
        let data = Fixtures.season()
        XCTAssertEqual(data.sessionCountByProgram["club"], 1)
        XCTAssertNil(data.sessionCountByProgram["combine"])
    }
}
