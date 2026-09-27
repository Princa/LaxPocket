import XCTest
@testable import LaxPocketCore

final class WorkloadTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar.laxWeek
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testWeekStartsOnMonday() {
        // Saturday, 26 Sep 2026 → Monday, 21 Sep 2026
        let start = Workload.startOfWeek(for: date(2026, 9, 26), calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: start), 2)
        XCTAssertEqual(calendar.component(.day, from: start), 21)
    }

    func testHoursByCategory() {
        let sessions = [
            TrainingSession(date: date(2026, 9, 21), programID: "a", category: .team, minutes: 90, effort: 7),
            TrainingSession(date: date(2026, 9, 22), programID: "b", category: .skills, minutes: 60, effort: 6),
            TrainingSession(date: date(2026, 9, 23), programID: "c", category: .fitness, minutes: 30, effort: 8)
        ]
        let hours = Workload.hours(for: sessions)
        XCTAssertEqual(hours.team, 1.5, accuracy: 1e-9)
        XCTAssertEqual(hours.skills, 1.0, accuracy: 1e-9)
        XCTAssertEqual(hours.fitness, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hours.total, 3.0, accuracy: 1e-9)
        XCTAssertEqual(hours.share(of: .team), 0.5, accuracy: 1e-9)
        XCTAssertEqual(sessions[0].load, 630)
    }

    func testWeeksAreOldestFirstAndBucketed() {
        let sessions = [
            TrainingSession(date: date(2026, 9, 14), programID: "a", category: .team, minutes: 60, effort: 5),
            TrainingSession(date: date(2026, 9, 20, 23), programID: "a", category: .team, minutes: 60, effort: 5), // Sunday, still last week
            TrainingSession(date: date(2026, 9, 21, 7), programID: "a", category: .skills, minutes: 120, effort: 5)
        ]
        let weeks = Workload.weeks(endingAt: date(2026, 9, 26), count: 3, sessions: sessions, calendar: calendar)
        XCTAssertEqual(weeks.count, 3)
        XCTAssertLessThan(weeks[0].weekStart, weeks[2].weekStart)
        XCTAssertEqual(weeks[0].hours.total, 0, accuracy: 1e-9)
        XCTAssertEqual(weeks[1].hours.team, 2, accuracy: 1e-9)
        XCTAssertEqual(weeks[2].hours.skills, 2, accuracy: 1e-9)
        XCTAssertEqual(weeks[2].sessionCount, 1)
    }

    func testAcuteChronicRatioAndZones() throws {
        let ratio = try XCTUnwrap(Workload.acuteChronicRatio(currentWeekHours: 11, previousWeekHours: [8, 9.5, 10.5, 10.5]))
        XCTAssertEqual(ratio, 11 / 9.625, accuracy: 1e-9)
        XCTAssertEqual(Workload.zone(for: ratio), .sweetSpot)
        XCTAssertEqual(Workload.zone(for: 0.6), .low)
        XCTAssertEqual(Workload.zone(for: 1.4), .caution)
        XCTAssertEqual(Workload.zone(for: 1.7), .high)
        XCTAssertNil(Workload.acuteChronicRatio(currentWeekHours: 5, previousWeekHours: []))
        XCTAssertNil(Workload.acuteChronicRatio(currentWeekHours: 5, previousWeekHours: [0, 0]))
    }

    func testEffortLabels() {
        XCTAssertEqual(TrainingSession.effortLabel(1), "Very easy")
        XCTAssertEqual(TrainingSession.effortLabel(6), "Moderate")
        XCTAssertEqual(TrainingSession.effortLabel(8), "Hard")
        XCTAssertEqual(TrainingSession.effortLabel(10), "Max effort")
    }
}
