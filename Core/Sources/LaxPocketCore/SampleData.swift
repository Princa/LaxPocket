import Foundation

/// A realistic sample season so every screen has something to show on first launch.
/// All numbers here are made up. Real data is entered in the app and stays on the device.
public enum SampleData {
    public static let programs: [Program] = [
        Program(id: "team-ontario", name: "Team Ontario U15", detail: "Provincial field team", group: .teams, sessionCategory: .team, monogram: "TO"),
        Program(id: "rockstar", name: "Rockstar 2031", detail: "Club team", group: .teams, sessionCategory: .team, monogram: "R31"),
        Program(id: "silvermaple", name: "SilverMaple League", detail: "League play", group: .teams, sessionCategory: .team, monogram: "SM"),
        Program(id: "nextlevel", name: "NextLevel Lacrosse", detail: "Private coaching", group: .skills, sessionCategory: .skills, monogram: "NL"),
        Program(id: "in-the-shoes", name: "Eric Evans · In the Shoes", detail: "Skill work · every Thursday", group: .skills, sessionCategory: .skills, monogram: "EE"),
        Program(id: "oaa", name: "OAA Dryland Training", detail: "Athleticism & conditioning", group: .fitness, sessionCategory: .fitness, monogram: "OAA"),
        Program(id: "quarry", name: "The Quarry Fitness Training", detail: "Strength & fitness development", group: .fitness, sessionCategory: .fitness, monogram: "Q"),
        Program(id: "dodgecity", name: "DodgeCity", detail: "Facility membership plan", group: .fitness, sessionCategory: .skills, monogram: "DC"),
        Program(id: "unc-showcase", name: "UNC Showcase & Camp", detail: "University of North Carolina · Dec 2026", group: .showcases, sessionCategory: nil, monogram: "UNC"),
        Program(id: "mental-coach", name: "Mental performance coach", detail: "Docs in Google Drive", group: .mental, sessionCategory: nil, monogram: "MC"),
        Program(id: "ndtp-combine", name: "Team Canada Combine", detail: "NDTP baseline & re-tests", group: .combine, sessionCategory: nil, monogram: "TC")
    ]

    /// Weekly pattern: (program, category, minutes, effort, weekday 1=Mon, focus).
    private static let weeklyPattern: [(String, SessionCategory, Int, Int, Int, [String])] = [
        ("quarry", .fitness, 60, 8, 1, ["Strength"]),
        ("rockstar", .team, 90, 7, 1, ["Dodging", "Defence"]),
        ("oaa", .fitness, 60, 7, 2, ["Conditioning"]),
        ("rockstar", .team, 90, 7, 3, ["Draw controls"]),
        ("in-the-shoes", .skills, 60, 7, 4, ["Dodging"]),
        ("quarry", .fitness, 60, 8, 4, ["Strength"]),
        ("dodgecity", .skills, 90, 5, 5, ["Stick skills", "Shooting"]),
        ("nextlevel", .skills, 60, 6, 6, ["Shooting", "Dodging"]),
        ("team-ontario", .team, 90, 7, 6, ["Draw controls", "Defence"])
    ]

    public static func make(referenceDate now: Date = Date(), calendar: Calendar = .laxWeek) -> AppData {
        let weekStart = Workload.startOfWeek(for: now, calendar: calendar)
        func day(_ weeksAgo: Int, _ weekday: Int, hour: Int = 18) -> Date {
            let base = calendar.date(byAdding: .day, value: -7 * weeksAgo + (weekday - 1), to: weekStart) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        }
        func daysFromNow(_ days: Int, hour: Int = 10) -> Date {
            let base = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        }

        // Six weeks of sessions, ramping up, only up to "now" in the current week.
        var sessions: [TrainingSession] = []
        let skipByWeek: [Int: Set<Int>] = [5: [3, 8], 4: [8], 3: [], 2: [], 1: [2], 0: []]
        for weeksAgo in (0...5).reversed() {
            for (index, item) in weeklyPattern.enumerated() {
                if skipByWeek[weeksAgo, default: []].contains(index) { continue }
                let date = day(weeksAgo, item.4, hour: item.0 == "team-ontario" ? 10 : 18)
                guard date <= now else { continue }
                sessions.append(TrainingSession(date: date, programID: item.0, category: item.1, minutes: item.2, effort: item.3, focus: item.5))
            }
        }

        let combine = CombineResult(
            date: day(10, 3, hour: 9),
            event: "Sample baseline",
            measurements: [
                .init(metric: .gripLeft, value: 262), .init(metric: .gripRight, value: 285),
                .init(metric: .squatJump, value: 9.8), .init(metric: .countermovementJump, value: 11.2),
                .init(metric: .sprint10m, value: 1.965),
                .init(metric: .proAgilityLeft, value: 5.02), .init(metric: .proAgilityRight, value: 5.07)
            ],
            isSample: true
        )

        let sampleURL = URL(string: "https://docs.google.com/document/")!
        let events: [SeasonEvent] = [
            SeasonEvent(kind: .game, title: "vs Burlington", team: "SilverMaple League", opponent: "Burlington", date: day(1, 7, hour: 12), location: "[Venue]",
                        ourScore: 11, theirScore: 7,
                        stats: GameStats(goals: 2, assists: 1, shots: 5, groundBalls: 4, drawControls: 3, causedTurnovers: 1),
                        focus: [FocusGoal(text: "Win 3+ draw controls", outcome: .hit, note: "Won 3"),
                                FocusGoal(text: "Attack the cage left-handed off the dodge", outcome: .partly, note: "1 left-hand shot"),
                                FocusGoal(text: "Talk on defence every possession", outcome: .hit, note: "Coach called it out")],
                        reflection: Reflection(selfRating: 7, wentWell: "Won 3 draws in the first half and kept winning ground balls in traffic.",
                                               workOn: "Left-hand finishing — two low-left shots went wide.",
                                               coachFeedback: "Good draw positioning and hustle. Keep your stick up on defence and look for the cutter before you dodge.",
                                               coachFeedbackDate: day(0, 1)),
                        videos: [VideoLink(title: "Highlights", url: URL(string: "https://www.youtube.com/")!, durationText: "2:14")]),
            SeasonEvent(kind: .game, title: "vs Mississauga", team: "SilverMaple League", opponent: "Mississauga", date: day(2, 7, hour: 12), location: "[Venue]",
                        ourScore: 6, theirScore: 8, stats: GameStats(goals: 1, assists: 0, shots: 4, groundBalls: 3, drawControls: 4, causedTurnovers: 0)),
            SeasonEvent(kind: .game, title: "vs Hamilton", team: "Rockstar 2031", opponent: "Hamilton", date: day(3, 7, hour: 12), location: "[Venue]",
                        ourScore: 10, theirScore: 4, stats: GameStats(goals: 2, assists: 2, shots: 6, groundBalls: 5, drawControls: 2, causedTurnovers: 1)),
            SeasonEvent(kind: .game, title: "vs Whitby", team: "SilverMaple League", opponent: "Whitby", date: daysFromNow(7), location: "[Venue]"),
            SeasonEvent(kind: .tournament, title: "Tournament weekend", team: "Rockstar 2031", date: daysFromNow(21), endDate: daysFromNow(22), location: "[Tournament, venue]"),
            SeasonEvent(kind: .showcase, title: "UNC Showcase & Camp", team: "Showcase", date: daysFromNow(70), dateIsTentative: true, location: "Chapel Hill, NC",
                        checklist: [ChecklistItem(title: "Registration", done: true), ChecklistItem(title: "Highlight reel", done: true),
                                    ChecklistItem(title: "Flights"), ChecklistItem(title: "Hotel"), ChecklistItem(title: "Intro email to coaches")])
        ]

        let expenses: [Expense] = [
            Expense(date: day(3, 3), title: "Team Ontario U15 · registration", category: .teamFees, amount: 1200),
            Expense(date: day(5, 1), title: "Rockstar 2031 · season fee", category: .teamFees, amount: 1850),
            Expense(date: day(5, 2), title: "SilverMaple League · registration", category: .teamFees, amount: 400),
            Expense(date: day(0, 4), title: "Eric Evans · 4-session pack", category: .coaching, amount: 320),
            Expense(date: day(4, 2), title: "NextLevel Lacrosse · package", category: .coaching, amount: 1600),
            Expense(date: day(2, 3), title: "The Quarry · monthly", category: .fitness, amount: 230),
            Expense(date: day(4, 3), title: "OAA Dryland · fall block", category: .fitness, amount: 1150),
            Expense(date: day(3, 6), title: "Tournament travel & hotel", category: .travel, amount: 1150),
            Expense(date: day(1, 5), title: "UNC Showcase · deposit", category: .showcases, amount: 650, note: "Paid in USD"),
            Expense(date: day(5, 4), title: "New head & mesh", category: .equipment, amount: 540),
            Expense(date: day(1, 1), title: "DodgeCity · monthly", category: .facility, amount: 420, note: "3 months")
        ]

        let docs: [MentalDoc] = [
            MentalDoc(title: "Pre-game routine", url: sampleURL, folder: .routines, kind: .word, status: .toReview, updatedAt: day(0, 4), updatedBy: "Coach", note: "3 comments"),
            MentalDoc(title: "Session 4 notes", url: sampleURL, folder: .sessionNotes, kind: .word, status: .new, updatedAt: day(0, 3), updatedBy: "Coach"),
            MentalDoc(title: "Game-day self-talk cues", url: sampleURL, folder: .routines, kind: .googleDoc, status: .reviewed, updatedAt: day(1, 7), updatedBy: "Athlete"),
            MentalDoc(title: "Post-game reflection journal", url: sampleURL, folder: .journal, kind: .googleDoc, status: .reviewed, updatedAt: day(1, 7), updatedBy: "Athlete"),
            MentalDoc(title: "Session 3 notes", url: sampleURL, folder: .sessionNotes, kind: .word, status: .reviewed, updatedAt: day(2, 3), updatedBy: "Coach"),
            MentalDoc(title: "Season goals", url: sampleURL, folder: .goals, kind: .word, status: .reviewed, updatedAt: day(4, 3), updatedBy: "Athlete")
        ]

        let profile = AthleteProfile(firstName: "Athlete", classYear: 2031, positions: "Midfield / Attack", benchmarkGroup: .u15Women,
                                     mentalCoachName: "", weeklyGoalHours: 12, season: "2026/27")

        return AppData(profile: profile, programs: programs, sessions: sessions, combineResults: [combine], events: events,
                       expenses: expenses, seasonBudget: 14_000, docs: docs, themeID: ThemeCatalog.defaultID, isSample: true)
    }
}
