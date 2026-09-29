import Foundation
@testable import LaxPocketCore

/// A small made-up season that touches every kind of record. Test-only; the app ships with no sample data.
enum Fixtures {
    static let start = Date(timeIntervalSince1970: 1_790_000_000) // Sep 2026

    static func day(_ offset: Int, hour: Int = 18) -> Date {
        start.addingTimeInterval(TimeInterval(offset * 86_400 + hour * 3_600))
    }

    static func season(name: String = "Sam") -> AppData {
        let programs = [
            Program(id: "club", name: "Club 2031", detail: "Club team", group: .teams, sessionCategory: .team, monogram: "C31"),
            Program(id: "skills-coach", name: "Skills coach", detail: "Private coaching", group: .skills, sessionCategory: .skills, monogram: "SC"),
            Program(id: "gym", name: "Strength gym", detail: "Strength & fitness", group: .fitness, sessionCategory: .fitness, monogram: "G"),
            Program(id: "combine", name: "Combine", detail: "Testing days", group: .combine, sessionCategory: nil, monogram: "TC")
        ]
        let sessions = [
            TrainingSession(date: day(0), programID: "club", category: .team, minutes: 90, effort: 7, focus: ["Dodging", "Defence"]),
            TrainingSession(date: day(1), programID: "gym", category: .fitness, minutes: 60, effort: 8, focus: ["Strength"], notes: "New squat PB"),
            TrainingSession(date: day(2), programID: "skills-coach", category: .skills, minutes: 60, effort: 6)
        ]
        let combine = CombineResult(date: day(-30, hour: 9), event: "Baseline", measurements: [
            .init(metric: .gripLeft, value: 262), .init(metric: .gripRight, value: 285),
            .init(metric: .sprint10m, value: 1.965), .init(metric: .proAgilityLeft, value: 5.02)
        ], heightText: "5′3″", weightText: "")
        let events = [
            SeasonEvent(kind: .game, title: "vs Rivals", team: "Club 2031", opponent: "Rivals", date: day(3, hour: 12), location: "Home field",
                        ourScore: 11, theirScore: 7,
                        stats: GameStats(goals: 2, assists: 1, shots: 5, groundBalls: 4, drawControls: 3, causedTurnovers: 1),
                        focus: [FocusGoal(text: "Win 3+ draws", outcome: .hit, note: "Won 3"), FocusGoal(text: "Left-hand finishing")],
                        reflection: Reflection(selfRating: 7, wentWell: "Draws", workOn: "Left hand", coachFeedback: "Stick up on D", coachFeedbackDate: day(4)),
                        videos: [VideoLink(title: "Highlights", url: URL(string: "https://example.com/v/1")!, durationText: "2:14")]),
            SeasonEvent(kind: .showcase, title: "Fall showcase", team: "Showcase", date: day(60, hour: 9), endDate: day(61, hour: 17), dateIsTentative: true,
                        location: "Somewhere, ON",
                        checklist: [ChecklistItem(title: "Registration", done: true), ChecklistItem(title: "Flights")])
        ]
        let expenses = [
            Expense(date: day(-10), title: "Club 2031 · season fee", category: .teamFees, amount: 1850),
            Expense(date: day(-2), title: "Skills coach · 4-pack", category: .coaching, amount: 320.5, note: "Paid in USD")
        ]
        let docs = [
            MentalDoc(title: "Pre-game routine", url: URL(string: "https://docs.google.com/document/d/abc/edit?rtpof=true")!, folder: .routines,
                      status: .toReview, updatedAt: day(1), updatedBy: "Coach", note: "3 comments")
        ]
        let profile = AthleteProfile(firstName: name, classYear: 2031, positions: "Midfield", benchmarkGroup: .u15Women,
                                     mentalCoachName: "Coach K", weeklyGoalHours: 12.5, season: "2026/27")
        return AppData(profile: profile, programs: programs, sessions: sessions, combineResults: [combine], events: events,
                       expenses: expenses, seasonBudget: 14_000, docs: docs, themeID: "northwestern")
    }
}
