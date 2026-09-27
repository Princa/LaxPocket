import Foundation

// Rows as they are stored in Supabase. Each struct matches one table in
// supabase/migrations/*_laxpocket_schema.sql, column for column, so the sync can
// send and receive them without any other mapping. `columns` lists what the app
// writes; server-managed columns (created_by, created_at, updated_at, currency)
// are left alone.

/// A table the app reads and writes.
public protocol CloudRow: Codable, Hashable, Sendable {
    static var table: String { get }
    /// Columns the app writes, in order.
    static var columns: [String] { get }
    /// Columns that identify a row, for `on_conflict`.
    static var conflictColumns: [String] { get }
}

public struct ProfileRow: CloudRow {
    public static let table = "profiles"
    public static let columns = ["id", "first_name", "class_year", "positions", "benchmark_group", "mental_coach_name",
                                 "weekly_goal_hours", "season_label", "season_budget", "theme_id"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var firstName: String
    public var classYear: Int?
    public var positions: String
    public var benchmarkGroup: BenchmarkGroup
    public var mentalCoachName: String
    public var weeklyGoalHours: Double
    public var seasonLabel: String
    public var seasonBudget: Double
    public var themeID: String

    enum CodingKeys: String, CodingKey {
        case id, positions
        case firstName = "first_name", classYear = "class_year", benchmarkGroup = "benchmark_group"
        case mentalCoachName = "mental_coach_name", weeklyGoalHours = "weekly_goal_hours", seasonLabel = "season_label"
        case seasonBudget = "season_budget", themeID = "theme_id"
    }
}

public struct ProgramRow: CloudRow {
    public static let table = "programs"
    public static let columns = ["profile_id", "id", "name", "detail", "program_group", "session_category", "monogram", "sort_order"]
    public static let conflictColumns = ["profile_id", "id"]

    public var profileID: UUID
    public var id: String
    public var name: String
    public var detail: String
    public var programGroup: ProgramGroup
    public var sessionCategory: SessionCategory?
    public var monogram: String
    public var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, detail, monogram
        case profileID = "profile_id", programGroup = "program_group", sessionCategory = "session_category", sortOrder = "sort_order"
    }
}

public struct SessionRow: CloudRow {
    public static let table = "training_sessions"
    public static let columns = ["id", "profile_id", "program_id", "started_at", "category", "minutes", "effort", "focus", "notes"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var programID: String
    public var startedAt: Timestamp
    public var category: SessionCategory
    public var minutes: Int
    public var effort: Int
    public var focus: [String]
    public var notes: String

    enum CodingKeys: String, CodingKey {
        case id, category, minutes, effort, focus, notes
        case profileID = "profile_id", programID = "program_id", startedAt = "started_at"
    }
}

public struct CombineResultRow: CloudRow {
    public static let table = "combine_results"
    public static let columns = ["id", "profile_id", "tested_at", "event_name", "height_text", "weight_text"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var testedAt: Timestamp
    public var eventName: String
    public var heightText: String
    public var weightText: String

    enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id", testedAt = "tested_at", eventName = "event_name", heightText = "height_text", weightText = "weight_text"
    }
}

public struct CombineMeasurementRow: CloudRow {
    public static let table = "combine_measurements"
    public static let columns = ["result_id", "profile_id", "metric", "value"]
    public static let conflictColumns = ["result_id", "metric"]

    public var resultID: UUID
    public var profileID: UUID
    public var metric: CombineMetric
    public var value: Double

    enum CodingKeys: String, CodingKey {
        case metric, value
        case resultID = "result_id", profileID = "profile_id"
    }
}

public struct EventRow: CloudRow {
    public static let table = "season_events"
    public static let columns = ["id", "profile_id", "kind", "title", "team", "opponent", "starts_at", "ends_at",
                                 "date_is_tentative", "location", "our_score", "their_score"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var kind: EventKind
    public var title: String
    public var team: String
    public var opponent: String?
    public var startsAt: Timestamp
    public var endsAt: Timestamp?
    public var dateIsTentative: Bool
    public var location: String
    public var ourScore: Int?
    public var theirScore: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, team, opponent, location
        case profileID = "profile_id", startsAt = "starts_at", endsAt = "ends_at", dateIsTentative = "date_is_tentative"
        case ourScore = "our_score", theirScore = "their_score"
    }
}

public struct GameStatsRow: CloudRow {
    public static let table = "game_stats"
    public static let columns = ["event_id", "profile_id", "goals", "assists", "shots", "ground_balls", "draw_controls", "caused_turnovers"]
    public static let conflictColumns = ["event_id"]

    public var eventID: UUID
    public var profileID: UUID
    public var goals: Int
    public var assists: Int
    public var shots: Int
    public var groundBalls: Int
    public var drawControls: Int
    public var causedTurnovers: Int

    enum CodingKeys: String, CodingKey {
        case goals, assists, shots
        case eventID = "event_id", profileID = "profile_id", groundBalls = "ground_balls", drawControls = "draw_controls"
        case causedTurnovers = "caused_turnovers"
    }
}

public struct ReflectionRow: CloudRow {
    public static let table = "game_reflections"
    public static let columns = ["event_id", "profile_id", "self_rating", "went_well", "work_on", "coach_feedback", "coach_feedback_at"]
    public static let conflictColumns = ["event_id"]

    public var eventID: UUID
    public var profileID: UUID
    public var selfRating: Int?
    public var wentWell: String
    public var workOn: String
    public var coachFeedback: String
    public var coachFeedbackAt: Timestamp?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", profileID = "profile_id", selfRating = "self_rating", wentWell = "went_well"
        case workOn = "work_on", coachFeedback = "coach_feedback", coachFeedbackAt = "coach_feedback_at"
    }
}

public struct FocusGoalRow: CloudRow {
    public static let table = "event_focus_goals"
    public static let columns = ["id", "event_id", "profile_id", "position", "goal", "outcome", "note"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var eventID: UUID
    public var profileID: UUID
    public var position: Int
    public var goal: String
    public var outcome: FocusOutcome
    public var note: String

    enum CodingKeys: String, CodingKey {
        case id, position, goal, outcome, note
        case eventID = "event_id", profileID = "profile_id"
    }
}

public struct VideoRow: CloudRow {
    public static let table = "event_videos"
    public static let columns = ["id", "event_id", "profile_id", "position", "title", "url", "duration_text"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var eventID: UUID
    public var profileID: UUID
    public var position: Int
    public var title: String
    public var url: String
    public var durationText: String

    enum CodingKeys: String, CodingKey {
        case id, position, title, url
        case eventID = "event_id", profileID = "profile_id", durationText = "duration_text"
    }
}

public struct ChecklistItemRow: CloudRow {
    public static let table = "event_checklist_items"
    public static let columns = ["id", "event_id", "profile_id", "position", "title", "done"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var eventID: UUID
    public var profileID: UUID
    public var position: Int
    public var title: String
    public var done: Bool

    enum CodingKeys: String, CodingKey {
        case id, position, title, done
        case eventID = "event_id", profileID = "profile_id"
    }
}

public struct ExpenseRow: CloudRow {
    public static let table = "expenses"
    public static let columns = ["id", "profile_id", "spent_at", "title", "category", "amount", "note"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var spentAt: Timestamp
    public var title: String
    public var category: ExpenseCategory
    public var amount: Double
    public var note: String

    enum CodingKeys: String, CodingKey {
        case id, title, category, amount, note
        case profileID = "profile_id", spentAt = "spent_at"
    }
}

public struct MentalDocRow: CloudRow {
    public static let table = "mental_docs"
    public static let columns = ["id", "profile_id", "title", "url", "folder", "kind", "status", "doc_updated_at", "doc_updated_by", "note"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var title: String
    public var url: String
    public var folder: DocFolder
    public var kind: DocKind
    public var status: DocStatus
    public var docUpdatedAt: Timestamp
    public var docUpdatedBy: String
    public var note: String

    enum CodingKeys: String, CodingKey {
        case id, title, url, folder, kind, status, note
        case profileID = "profile_id", docUpdatedAt = "doc_updated_at", docUpdatedBy = "doc_updated_by"
    }
}

// MARK: - Groups that sync as one unit

/// A testing day with its results. Changing any result re-sends the whole day.
public struct CombineBundle: Codable, Hashable, Identifiable, Sendable {
    public var result: CombineResultRow
    /// In `CombineMetric.allCases` order.
    public var measurements: [CombineMeasurementRow]

    public var id: UUID { result.id }
}

/// An event with everything hanging off it. Changing any part re-sends the whole event.
public struct EventBundle: Codable, Hashable, Identifiable, Sendable {
    public var event: EventRow
    public var stats: GameStatsRow?
    public var reflection: ReflectionRow?
    /// Each list is in `position` order.
    public var focus: [FocusGoalRow]
    public var videos: [VideoRow]
    public var checklist: [ChecklistItemRow]

    public var id: UUID { event.id }
}

/// Everything stored for one athlete profile, as cloud rows.
public struct ProfileSnapshot: Codable, Hashable, Sendable {
    public var profile: ProfileRow
    public var programs: [ProgramRow]
    public var sessions: [SessionRow]
    public var combineResults: [CombineBundle]
    public var events: [EventBundle]
    public var expenses: [ExpenseRow]
    public var docs: [MentalDocRow]

    public init(profile: ProfileRow, programs: [ProgramRow] = [], sessions: [SessionRow] = [], combineResults: [CombineBundle] = [],
                events: [EventBundle] = [], expenses: [ExpenseRow] = [], docs: [MentalDocRow] = []) {
        self.profile = profile
        self.programs = programs
        self.sessions = sessions
        self.combineResults = combineResults
        self.events = events
        self.expenses = expenses
        self.docs = docs
    }
}

// MARK: - App data → rows

private func roundedTo(_ places: Double, _ value: Double) -> Double {
    let scale = pow(10, places)
    return (value * scale).rounded() / scale
}

extension ProfileRow {
    init(_ data: AppData) {
        let p = data.profile
        id = data.id
        firstName = p.firstName
        // The column only takes graduation years; anything else is left blank rather than failing the sync.
        classYear = p.classYear.flatMap { (2000...2100).contains($0) ? $0 : nil }
        positions = p.positions
        benchmarkGroup = p.benchmarkGroup
        mentalCoachName = p.mentalCoachName
        weeklyGoalHours = min(max(roundedTo(1, p.weeklyGoalHours), 0.5), 60)
        seasonLabel = p.season
        seasonBudget = roundedTo(2, data.seasonBudget)
        themeID = data.themeID
    }
}

extension ProfileSnapshot {
    /// The rows that represent a profile's data.
    public init(_ data: AppData) {
        let pid = data.id
        profile = ProfileRow(data)
        programs = data.programs.enumerated().map { index, p in
            ProgramRow(profileID: pid, id: p.id, name: p.name, detail: p.detail, programGroup: p.group,
                       sessionCategory: p.sessionCategory, monogram: p.monogram, sortOrder: index)
        }
        sessions = data.sessions.map { s in
            SessionRow(id: s.id, profileID: pid, programID: s.programID, startedAt: Timestamp(s.date), category: s.category,
                       minutes: s.minutes, effort: s.effort, focus: s.focus, notes: s.notes)
        }
        combineResults = data.combineResults.map { r in
            var byMetric: [CombineMetric: Double] = [:]
            for m in r.measurements { byMetric[m.metric] = m.value }
            return CombineBundle(
                result: CombineResultRow(id: r.id, profileID: pid, testedAt: Timestamp(r.date), eventName: r.event,
                                         heightText: r.heightText, weightText: r.weightText),
                measurements: CombineMetric.allCases.compactMap { metric in
                    byMetric[metric].map { CombineMeasurementRow(resultID: r.id, profileID: pid, metric: metric, value: $0) }
                }
            )
        }
        events = data.events.map { e in
            EventBundle(
                event: EventRow(id: e.id, profileID: pid, kind: e.kind, title: e.title, team: e.team, opponent: e.opponent,
                                startsAt: Timestamp(e.date), endsAt: e.endDate.map(Timestamp.init), dateIsTentative: e.dateIsTentative,
                                location: e.location, ourScore: e.hasResult ? e.ourScore : nil, theirScore: e.hasResult ? e.theirScore : nil),
                stats: e.stats.map { s in
                    GameStatsRow(eventID: e.id, profileID: pid, goals: s.goals, assists: s.assists, shots: s.shots,
                                 groundBalls: s.groundBalls, drawControls: s.drawControls, causedTurnovers: s.causedTurnovers)
                },
                reflection: e.reflection.map { r in
                    ReflectionRow(eventID: e.id, profileID: pid, selfRating: r.selfRating, wentWell: r.wentWell, workOn: r.workOn,
                                  coachFeedback: r.coachFeedback, coachFeedbackAt: r.coachFeedbackDate.map(Timestamp.init))
                },
                focus: e.focus.enumerated().map { index, g in
                    FocusGoalRow(id: g.id, eventID: e.id, profileID: pid, position: index, goal: g.text, outcome: g.outcome, note: g.note)
                },
                videos: e.videos.enumerated().map { index, v in
                    VideoRow(id: v.id, eventID: e.id, profileID: pid, position: index, title: v.title, url: v.url.absoluteString,
                             durationText: v.durationText)
                },
                checklist: e.checklist.enumerated().map { index, c in
                    ChecklistItemRow(id: c.id, eventID: e.id, profileID: pid, position: index, title: c.title, done: c.done)
                }
            )
        }
        expenses = data.expenses.map { x in
            ExpenseRow(id: x.id, profileID: pid, spentAt: Timestamp(x.date), title: x.title, category: x.category,
                       amount: roundedTo(2, x.amount), note: x.note)
        }
        docs = data.docs.map { d in
            MentalDocRow(id: d.id, profileID: pid, title: d.title, url: d.url.absoluteString, folder: d.folder, kind: d.kind,
                         status: d.status, docUpdatedAt: Timestamp(d.updatedAt), docUpdatedBy: d.updatedBy, note: d.note)
        }
    }

    // MARK: - Rows → app data

    /// The profile's data rebuilt from rows, sorted the way the app lists things.
    public var appData: AppData {
        let p = profile
        let athlete = AthleteProfile(firstName: p.firstName, classYear: p.classYear, positions: p.positions, benchmarkGroup: p.benchmarkGroup,
                                     mentalCoachName: p.mentalCoachName, weeklyGoalHours: p.weeklyGoalHours, season: p.seasonLabel)
        return AppData(
            id: p.id,
            profile: athlete,
            programs: programs.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.map { r in
                Program(id: r.id, name: r.name, detail: r.detail, group: r.programGroup, sessionCategory: r.sessionCategory, monogram: r.monogram)
            },
            sessions: sessions.sorted { $0.startedAt < $1.startedAt }.map { r in
                TrainingSession(id: r.id, date: r.startedAt.date, programID: r.programID, category: r.category, minutes: r.minutes,
                                effort: r.effort, focus: r.focus, notes: r.notes)
            },
            combineResults: combineResults.sorted { $0.result.testedAt < $1.result.testedAt }.map { b in
                CombineResult(id: b.result.id, date: b.result.testedAt.date, event: b.result.eventName,
                              measurements: b.measurements.map { CombineMeasurement(metric: $0.metric, value: $0.value) },
                              heightText: b.result.heightText, weightText: b.result.weightText)
            },
            events: events.sorted { $0.event.startsAt < $1.event.startsAt }.map(\.seasonEvent),
            expenses: expenses.sorted { $0.spentAt < $1.spentAt }.map { r in
                Expense(id: r.id, date: r.spentAt.date, title: r.title, category: r.category, amount: r.amount, note: r.note)
            },
            seasonBudget: p.seasonBudget,
            docs: docs.sorted { $0.docUpdatedAt > $1.docUpdatedAt }.compactMap { r in
                URL(string: r.url).map {
                    MentalDoc(id: r.id, title: r.title, url: $0, folder: r.folder, kind: r.kind, status: r.status,
                              updatedAt: r.docUpdatedAt.date, updatedBy: r.docUpdatedBy, note: r.note)
                }
            },
            themeID: p.themeID
        )
    }
}

extension EventBundle {
    var seasonEvent: SeasonEvent {
        let e = event
        return SeasonEvent(
            id: e.id, kind: e.kind, title: e.title, team: e.team, opponent: e.opponent,
            date: e.startsAt.date, endDate: e.endsAt?.date, dateIsTentative: e.dateIsTentative, location: e.location,
            ourScore: e.ourScore, theirScore: e.theirScore,
            stats: stats.map { s in
                GameStats(goals: s.goals, assists: s.assists, shots: s.shots, groundBalls: s.groundBalls,
                          drawControls: s.drawControls, causedTurnovers: s.causedTurnovers)
            },
            focus: focus.sorted { $0.position < $1.position }.map { FocusGoal(id: $0.id, text: $0.goal, outcome: $0.outcome, note: $0.note) },
            reflection: reflection.map { r in
                Reflection(selfRating: r.selfRating, wentWell: r.wentWell, workOn: r.workOn, coachFeedback: r.coachFeedback,
                           coachFeedbackDate: r.coachFeedbackAt?.date)
            },
            videos: videos.sorted { $0.position < $1.position }.compactMap { v in
                URL(string: v.url).map { VideoLink(id: v.id, title: v.title, url: $0, durationText: v.durationText) }
            },
            checklist: checklist.sorted { $0.position < $1.position }.map { ChecklistItem(id: $0.id, title: $0.title, done: $0.done) }
        )
    }
}

extension ProfileSnapshot {
    /// True when both hold the same rows, in any order.
    public func hasSameRows(as other: ProfileSnapshot) -> Bool {
        profile == other.profile
            && Set(programs) == Set(other.programs) && Set(sessions) == Set(other.sessions)
            && Set(combineResults) == Set(other.combineResults) && Set(events) == Set(other.events)
            && Set(expenses) == Set(other.expenses) && Set(docs) == Set(other.docs)
    }
}
