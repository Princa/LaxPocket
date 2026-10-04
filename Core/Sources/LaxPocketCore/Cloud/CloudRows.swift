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
                                 "weekly_goal_hours", "season_label", "season_budget", "theme_id", "body_units", "usd_to_cad"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var firstName: String
    public var classYear: Int?
    public var positions: String
    /// Null: not on an NDTP team.
    public var benchmarkGroup: BenchmarkGroup?
    public var mentalCoachName: String
    public var weeklyGoalHours: Double
    public var seasonLabel: String
    public var seasonBudget: Double
    public var themeID: String
    public var bodyUnits: BodyUnits
    public var usdToCAD: Double

    enum CodingKeys: String, CodingKey {
        case id, positions
        case firstName = "first_name", classYear = "class_year", benchmarkGroup = "benchmark_group"
        case mentalCoachName = "mental_coach_name", weeklyGoalHours = "weekly_goal_hours", seasonLabel = "season_label"
        case seasonBudget = "season_budget", themeID = "theme_id", bodyUnits = "body_units", usdToCAD = "usd_to_cad"
    }
}

extension ProfileRow {
    /// Sync records saved before height and weight tracking have no `body_units`, and those saved before currencies
    /// have no `usd_to_cad`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        firstName = try c.decode(String.self, forKey: .firstName)
        classYear = try c.decodeIfPresent(Int.self, forKey: .classYear)
        positions = try c.decode(String.self, forKey: .positions)
        benchmarkGroup = try c.decodeIfPresent(BenchmarkGroup.self, forKey: .benchmarkGroup)
        mentalCoachName = try c.decode(String.self, forKey: .mentalCoachName)
        weeklyGoalHours = try c.decode(Double.self, forKey: .weeklyGoalHours)
        seasonLabel = try c.decode(String.self, forKey: .seasonLabel)
        seasonBudget = try c.decode(Double.self, forKey: .seasonBudget)
        themeID = try c.decode(String.self, forKey: .themeID)
        bodyUnits = try c.decodeIfPresent(BodyUnits.self, forKey: .bodyUnits) ?? .imperial
        usdToCAD = try c.decodeIfPresent(Double.self, forKey: .usdToCAD) ?? ExchangeRate.defaultUSDToCAD
    }
}

public struct ProgramRow: CloudRow {
    public static let table = "programs"
    public static let columns = ["profile_id", "id", "name", "detail", "program_group", "session_category", "monogram", "sort_order",
                                 "first_season", "last_season"]
    public static let conflictColumns = ["profile_id", "id"]

    public var profileID: UUID
    public var id: String
    public var name: String
    public var detail: String
    public var programGroup: ProgramGroup
    public var sessionCategory: SessionCategory?
    public var monogram: String
    public var sortOrder: Int
    /// Nil on rows saved before programs had seasons.
    public var firstSeason: Int? = nil
    public var lastSeason: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, detail, monogram
        case profileID = "profile_id", programGroup = "program_group", sessionCategory = "session_category", sortOrder = "sort_order"
        case firstSeason = "first_season", lastSeason = "last_season"
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
    public static let columns = ["id", "profile_id", "spent_at", "title", "category", "amount", "note", "program_id", "season", "trip_id",
                                 "currency", "original_amount"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var spentAt: Timestamp
    public var title: String
    public var category: ExpenseCategory
    public var amount: Double
    public var note: String
    public var programID: String?
    public var season: Int
    public var tripID: UUID?
    public var currency: Currency
    public var originalAmount: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, category, amount, note, season, currency
        case profileID = "profile_id", spentAt = "spent_at", programID = "program_id", tripID = "trip_id", originalAmount = "original_amount"
    }
}

extension ExpenseRow {
    public init(id: UUID, profileID: UUID, spentAt: Timestamp, title: String, category: ExpenseCategory, amount: Double, note: String,
                programID: String? = nil, season: Int? = nil, tripID: UUID? = nil, currency: Currency = .cad, originalAmount: Double? = nil) {
        self.id = id
        self.profileID = profileID
        self.spentAt = spentAt
        self.title = title
        self.category = category
        self.amount = amount
        self.note = note
        self.programID = programID
        self.season = season ?? AthleteProfile.seasonStart(for: spentAt.date)
        self.tripID = tripID
        self.currency = currency
        self.originalAmount = originalAmount
    }

    /// Rows written before expenses had seasons (by an older build, or saved in a sync record) have no season; they
    /// count toward the season of `spent_at`, the same as on the phone. Rows from before trips have no `trip_id`, and rows from
    /// before currencies have no `currency` (they're CAD).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        profileID = try c.decode(UUID.self, forKey: .profileID)
        spentAt = try c.decode(Timestamp.self, forKey: .spentAt)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(ExpenseCategory.self, forKey: .category)
        amount = try c.decode(Double.self, forKey: .amount)
        note = try c.decode(String.self, forKey: .note)
        programID = try c.decodeIfPresent(String.self, forKey: .programID)
        season = try c.decodeIfPresent(Int.self, forKey: .season) ?? AthleteProfile.seasonStart(for: spentAt.date)
        tripID = try c.decodeIfPresent(UUID.self, forKey: .tripID)
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? .cad
        originalAmount = try c.decodeIfPresent(Double.self, forKey: .originalAmount)
    }
}

public struct TripRow: CloudRow {
    public static let table = "trips"
    public static let columns = ["id", "profile_id", "name", "destination", "country", "departs_at", "returns_at", "season", "program_id",
                                 "event_id", "budget", "travel_mode", "travel_details", "hotel_name", "hotel_address", "hotel_confirmation",
                                 "hotel_check_in", "hotel_check_out", "note"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var name: String
    public var destination: String
    public var country: TripCountry
    public var departsAt: Timestamp
    public var returnsAt: Timestamp
    public var season: Int
    public var programID: String?
    public var eventID: UUID?
    public var budget: Double
    public var travelMode: TravelMode
    public var travelDetails: String
    public var hotelName: String
    public var hotelAddress: String
    public var hotelConfirmation: String
    public var hotelCheckIn: Timestamp?
    public var hotelCheckOut: Timestamp?
    public var note: String

    enum CodingKeys: String, CodingKey {
        case id, name, destination, country, season, budget, note
        case profileID = "profile_id", departsAt = "departs_at", returnsAt = "returns_at", programID = "program_id", eventID = "event_id"
        case travelMode = "travel_mode", travelDetails = "travel_details", hotelName = "hotel_name", hotelAddress = "hotel_address"
        case hotelConfirmation = "hotel_confirmation", hotelCheckIn = "hotel_check_in", hotelCheckOut = "hotel_check_out"
    }
}

public struct SeasonBudgetRow: CloudRow {
    public static let table = "season_budgets"
    public static let columns = ["profile_id", "season", "amount", "note"]
    public static let conflictColumns = ["profile_id", "season"]

    public var profileID: UUID
    public var season: Int
    public var amount: Double
    public var note: String

    enum CodingKeys: String, CodingKey {
        case season, amount, note
        case profileID = "profile_id"
    }
}

public struct ProgramBudgetRow: CloudRow {
    public static let table = "program_budgets"
    public static let columns = ["profile_id", "program_id", "season", "amount", "note"]
    public static let conflictColumns = ["profile_id", "program_id", "season"]

    public struct Key: Hashable, Sendable {
        public var programID: String
        public var season: Int
    }

    public var profileID: UUID
    public var programID: String
    public var season: Int
    public var amount: Double
    public var note: String

    public var key: Key { Key(programID: programID, season: season) }

    enum CodingKeys: String, CodingKey {
        case season, amount, note
        case profileID = "profile_id", programID = "program_id"
    }
}

public struct MentalDocRow: CloudRow {
    public static let table = "mental_docs"
    /// `locked_by` is set by the database, never by the app.
    public static let columns = ["id", "profile_id", "title", "url", "folder", "kind", "status", "doc_updated_at", "doc_updated_by", "note",
                                 "visibility"]
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
    public var visibility: DocVisibility = .shared

    enum CodingKeys: String, CodingKey {
        case id, title, url, folder, kind, status, note, visibility
        case profileID = "profile_id", docUpdatedAt = "doc_updated_at", docUpdatedBy = "doc_updated_by"
    }
}

extension MentalDocRow {
    /// Sync records saved before locking have no `visibility`: those docs were shared.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), profileID: try c.decode(UUID.self, forKey: .profileID),
                  title: try c.decode(String.self, forKey: .title), url: try c.decode(String.self, forKey: .url),
                  folder: try c.decode(DocFolder.self, forKey: .folder), kind: try c.decode(DocKind.self, forKey: .kind),
                  status: try c.decode(DocStatus.self, forKey: .status), docUpdatedAt: try c.decode(Timestamp.self, forKey: .docUpdatedAt),
                  docUpdatedBy: try c.decode(String.self, forKey: .docUpdatedBy), note: try c.decode(String.self, forKey: .note),
                  visibility: try c.decodeIfPresent(DocVisibility.self, forKey: .visibility) ?? .shared)
    }
}

/// A locked mental doc as others on the athlete see it (the `locked_mental_docs` view). Read only.
public struct LockedMentalDocRow: Codable, Hashable, Sendable {
    public static let table = "locked_mental_docs"

    public var id: UUID
    public var profileID: UUID
    public var folder: DocFolder
    public var docUpdatedAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id, folder
        case profileID = "profile_id", docUpdatedAt = "doc_updated_at"
    }
}

// MARK: - Accounts and people

/// Who an account belongs to.
public struct AccountRow: CloudRow {
    public static let table = "accounts"
    public static let columns = ["user_id", "display_name", "kind"]
    public static let conflictColumns = ["user_id"]

    public var userID: UUID
    public var displayName: String
    public var kind: Relationship

    public init(userID: UUID, displayName: String, kind: Relationship) {
        self.userID = userID
        self.displayName = displayName
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case userID = "user_id", displayName = "display_name"
    }
}

/// An account on an athlete, with what it can do (`profile_members`, or `my_profile_access` for the signed-in account,
/// which has no `user_id`).
public struct MemberRow: Decodable, Hashable, Sendable {
    public static let table = "profile_members"
    public static let mine = "my_profile_access"

    public var profileID: UUID
    public var userID: UUID?
    public var role: MemberRole
    public var relationships: Set<Relationship>

    public var access: ProfileAccess { ProfileAccess(role: role, relationships: relationships) }

    enum CodingKeys: String, CodingKey {
        case role, relationships
        case profileID = "profile_id", userID = "user_id"
    }

    /// Relationships a newer schema adds are skipped rather than failing the sync.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try c.decode(UUID.self, forKey: .profileID)
        userID = try c.decodeIfPresent(UUID.self, forKey: .userID)
        role = try c.decode(MemberRole.self, forKey: .role)
        relationships = Set(try c.decode([String].self, forKey: .relationships).compactMap(Relationship.init(rawValue:)))
    }
}

/// An invite code for an athlete (`profile_invites`). Made and accepted through `create_profile_invite` and
/// `accept_profile_invite`.
public struct InviteRow: Decodable, Hashable, Identifiable, Sendable {
    public static let table = "profile_invites"

    public var code: String
    public var profileID: UUID
    public var relationship: Relationship
    public var createdAt: Timestamp
    public var expiresAt: Timestamp
    public var acceptedAt: Timestamp?

    public var id: String { code }

    /// Not used yet and not expired.
    public func isOpen(now: Date = Date()) -> Bool {
        acceptedAt == nil && expiresAt.date > now
    }

    public var displayCode: String { InviteRow.displayCode(code) }

    /// "ABCD2345" → "ABCD-2345": easier to read out or type.
    public static func displayCode(_ code: String) -> String {
        code.count == 8 ? "\(code.prefix(4))-\(code.suffix(4))" : code
    }

    enum CodingKeys: String, CodingKey {
        case code, relationship
        case profileID = "profile_id", createdAt = "created_at", expiresAt = "expires_at", acceptedAt = "accepted_at"
    }
}

public struct BodyMeasurementRow: CloudRow {
    public static let table = "body_measurements"
    public static let columns = ["id", "profile_id", "measured_at", "height_cm", "weight_kg", "note"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var measuredAt: Timestamp
    public var heightCm: Double?
    public var weightKg: Double?
    public var note: String

    enum CodingKeys: String, CodingKey {
        case id, note
        case profileID = "profile_id", measuredAt = "measured_at", heightCm = "height_cm", weightKg = "weight_kg"
    }
}

public struct WallballDrillRow: CloudRow {
    public static let table = "wallball_drills"
    public static let columns = ["profile_id", "id", "name", "detail", "hands", "default_reps", "hidden", "sort_order"]
    public static let conflictColumns = ["profile_id", "id"]

    public var profileID: UUID
    public var id: String
    public var name: String
    public var detail: String
    public var hands: DrillHands
    public var defaultReps: Int
    public var hidden: Bool
    public var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, detail, hands, hidden
        case profileID = "profile_id", defaultReps = "default_reps", sortOrder = "sort_order"
    }
}

public struct WallballSessionRow: CloudRow {
    public static let table = "wallball_sessions"
    public static let columns = ["id", "profile_id", "done_at", "minutes", "challenge_seconds", "notes"]
    public static let conflictColumns = ["id"]

    public var id: UUID
    public var profileID: UUID
    public var doneAt: Timestamp
    public var minutes: Int?
    public var challengeSeconds: Int?
    public var notes: String

    enum CodingKeys: String, CodingKey {
        case id, minutes, notes
        case profileID = "profile_id", doneAt = "done_at", challengeSeconds = "challenge_seconds"
    }
}

public struct WallballSetRow: CloudRow {
    public static let table = "wallball_sets"
    public static let columns = ["session_id", "profile_id", "drill_id", "hand", "reps", "position"]
    public static let conflictColumns = ["session_id", "drill_id", "hand"]

    public var sessionID: UUID
    public var profileID: UUID
    public var drillID: String
    public var hand: WallballHand
    public var reps: Int
    public var position: Int

    enum CodingKeys: String, CodingKey {
        case hand, reps, position
        case sessionID = "session_id", profileID = "profile_id", drillID = "drill_id"
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

/// A wall ball session with its sets. Changing any set re-sends the whole session.
public struct WallballBundle: Codable, Hashable, Identifiable, Sendable {
    public var session: WallballSessionRow
    /// In `position` order.
    public var sets: [WallballSetRow]

    public var id: UUID { session.id }
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
    public var bodyMeasurements: [BodyMeasurementRow]
    public var wallballDrills: [WallballDrillRow]
    public var wallballSessions: [WallballBundle]
    public var seasonBudgets: [SeasonBudgetRow]
    public var programBudgets: [ProgramBudgetRow]
    public var trips: [TripRow]
    /// Docs the athlete locked, as this account sees them. Read only: the sync takes the cloud's list as it is.
    public var lockedDocs: [LockedMentalDocRow]
    /// What this account can do with the athlete. Nil before the athlete is in the cloud.
    public var access: ProfileAccess?

    public init(profile: ProfileRow, programs: [ProgramRow] = [], sessions: [SessionRow] = [], combineResults: [CombineBundle] = [],
                events: [EventBundle] = [], expenses: [ExpenseRow] = [], docs: [MentalDocRow] = [], bodyMeasurements: [BodyMeasurementRow] = [],
                wallballDrills: [WallballDrillRow] = [], wallballSessions: [WallballBundle] = [], seasonBudgets: [SeasonBudgetRow] = [],
                programBudgets: [ProgramBudgetRow] = [], trips: [TripRow] = [], lockedDocs: [LockedMentalDocRow] = [], access: ProfileAccess? = nil) {
        self.profile = profile
        self.programs = programs
        self.sessions = sessions
        self.combineResults = combineResults
        self.events = events
        self.expenses = expenses
        self.docs = docs
        self.bodyMeasurements = bodyMeasurements
        self.wallballDrills = wallballDrills
        self.wallballSessions = wallballSessions
        self.seasonBudgets = seasonBudgets
        self.programBudgets = programBudgets
        self.trips = trips
        self.lockedDocs = lockedDocs
        self.access = access
    }

    private enum CodingKeys: String, CodingKey {
        case profile, programs, sessions, combineResults, events, expenses, docs, bodyMeasurements, wallballDrills, wallballSessions,
             seasonBudgets, programBudgets, trips, lockedDocs, access
    }

    /// Sync records saved before height and weight tracking have no `bodyMeasurements`, those saved before
    /// wall ball have no `wallballDrills` or `wallballSessions`, those saved before budgets per season have
    /// no `seasonBudgets` or `programBudgets`, those saved before trips have no `trips`, and those saved before family
    /// accounts have no `lockedDocs` or `access`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(ProfileRow.self, forKey: .profile)
        programs = try c.decode([ProgramRow].self, forKey: .programs)
        sessions = try c.decode([SessionRow].self, forKey: .sessions)
        combineResults = try c.decode([CombineBundle].self, forKey: .combineResults)
        events = try c.decode([EventBundle].self, forKey: .events)
        expenses = try c.decode([ExpenseRow].self, forKey: .expenses)
        docs = try c.decode([MentalDocRow].self, forKey: .docs)
        bodyMeasurements = try c.decodeIfPresent([BodyMeasurementRow].self, forKey: .bodyMeasurements) ?? []
        wallballDrills = try c.decodeIfPresent([WallballDrillRow].self, forKey: .wallballDrills) ?? []
        wallballSessions = try c.decodeIfPresent([WallballBundle].self, forKey: .wallballSessions) ?? []
        seasonBudgets = try c.decodeIfPresent([SeasonBudgetRow].self, forKey: .seasonBudgets) ?? []
        programBudgets = try c.decodeIfPresent([ProgramBudgetRow].self, forKey: .programBudgets) ?? []
        trips = try c.decodeIfPresent([TripRow].self, forKey: .trips) ?? []
        lockedDocs = try c.decodeIfPresent([LockedMentalDocRow].self, forKey: .lockedDocs) ?? []
        access = try c.decodeIfPresent(ProfileAccess.self, forKey: .access)
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
        bodyUnits = p.bodyUnits
        usdToCAD = ExchangeRate.normalized(p.usdToCAD)
    }
}

extension BodyMeasurementRow {
    /// Rounded to what the database stores. A value outside the accepted range is left out, and a measurement
    /// with neither value has no row, rather than failing the sync.
    init?(_ m: BodyMeasurement, profileID: UUID) {
        var height: Double? = m.heightCm.map(BodyMeasurement.roundedHeight)
        if let value = height, !BodyMeasurement.heightRangeCm.contains(value) { height = nil }
        var weight: Double? = m.weightKg.map(BodyMeasurement.roundedWeight)
        if let value = weight, !BodyMeasurement.weightRangeKg.contains(value) { weight = nil }
        guard height != nil || weight != nil else { return nil }
        self.init(id: m.id, profileID: profileID, measuredAt: Timestamp(m.date), heightCm: height, weightKg: weight, note: m.note)
    }
}

extension WallballDrillRow {
    /// Kept to what the database accepts: a name, and default reps in range.
    init(_ d: WallballDrill, profileID: UUID, sortOrder: Int) {
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let reps = WallballDrill.defaultRepsRange
        self.init(profileID: profileID, id: d.id, name: name.isEmpty ? "Drill" : name, detail: d.detail, hands: d.hands,
                  defaultReps: min(max(d.defaultReps, reps.lowerBound), reps.upperBound), hidden: d.isHidden, sortOrder: sortOrder)
    }
}

extension WallballBundle {
    /// One set per drill and hand, with reps in range. A time or challenge length the database wouldn't take is left out.
    init(_ s: WallballSession, profileID: UUID) {
        let minutes = s.minutes.flatMap { (1...1440).contains($0) ? $0 : nil }
        let seconds = s.challengeSeconds.flatMap { WallballChallenge.secondsRange.contains($0) ? $0 : nil }
        session = WallballSessionRow(id: s.id, profileID: profileID, doneAt: Timestamp(s.date), minutes: minutes,
                                     challengeSeconds: seconds, notes: s.notes)
        sets = WallballSession.normalized(s.sets).enumerated().map { index, set in
            WallballSetRow(sessionID: s.id, profileID: profileID, drillID: set.drillID, hand: set.hand, reps: set.reps, position: index)
        }
    }
}

extension ProfileSnapshot {
    /// The rows that represent a profile's data.
    public init(_ data: AppData) {
        let pid = data.id
        profile = ProfileRow(data)
        programs = data.programs.enumerated().map { index, p in
            // Seasons the database wouldn't take are left open-ended, and a range typed backwards is turned around.
            var first = p.firstSeason.flatMap(validSeason), last = p.lastSeason.flatMap(validSeason)
            if let f = first, let l = last, l < f { (first, last) = (l, f) }
            return ProgramRow(profileID: pid, id: p.id, name: p.name, detail: p.detail, programGroup: p.group,
                              sessionCategory: p.sessionCategory, monogram: p.monogram, sortOrder: index, firstSeason: first, lastSeason: last)
        }
        let programIDs = Set(data.programs.map(\.id))
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
        let eventIDs = Set(data.events.map(\.id))
        trips = data.trips.map { t in
            // Dates typed backwards are turned around, the same as program seasons.
            let departs = min(t.departureDate, t.returnDate), returns = max(t.departureDate, t.returnDate)
            var checkIn = t.hotelCheckIn, checkOut = t.hotelCheckOut
            if let a = checkIn, let b = checkOut, b < a { (checkIn, checkOut) = (b, a) }
            return TripRow(id: t.id, profileID: pid, name: t.name, destination: t.destination, country: t.country,
                           departsAt: Timestamp(departs), returnsAt: Timestamp(returns),
                           season: validSeason(t.season) ?? AthleteProfile.seasonStart(for: departs),
                           programID: t.programID.flatMap { programIDs.contains($0) ? $0 : nil },
                           eventID: t.eventID.flatMap { eventIDs.contains($0) ? $0 : nil },
                           budget: max(roundedTo(2, t.budget), 0), travelMode: t.travelMode, travelDetails: t.travelDetails,
                           hotelName: t.hotelName, hotelAddress: t.hotelAddress, hotelConfirmation: t.hotelConfirmation,
                           hotelCheckIn: checkIn.map(Timestamp.init), hotelCheckOut: checkOut.map(Timestamp.init), note: t.note)
        }
        let tripIDs = Set(data.trips.map(\.id))
        expenses = data.expenses.map { x in
            // A link to a program or trip that's gone would fail the foreign key, so it's dropped. An amount paid in
            // another currency that rounds to nothing is stored as CAD.
            let original = x.currency == .cad ? nil : x.originalAmount.map { roundedTo(2, $0) }.flatMap { $0 > 0 ? $0 : nil }
            return ExpenseRow(id: x.id, profileID: pid, spentAt: Timestamp(x.date), title: x.title, category: x.category,
                              amount: roundedTo(2, x.amount), note: x.note, programID: x.programID.flatMap { programIDs.contains($0) ? $0 : nil },
                              season: validSeason(x.season), tripID: x.tripID.flatMap { tripIDs.contains($0) ? $0 : nil },
                              currency: original == nil ? .cad : x.currency, originalAmount: original)
        }
        seasonBudgets = data.seasonBudgets.compactMap { b in
            guard let season = validSeason(b.season), roundedTo(2, b.amount) > 0 else { return nil }
            return SeasonBudgetRow(profileID: pid, season: season, amount: roundedTo(2, b.amount), note: b.note)
        }
        programBudgets = data.programBudgets.compactMap { b in
            guard programIDs.contains(b.programID), let season = validSeason(b.season), roundedTo(2, b.amount) > 0 else { return nil }
            return ProgramBudgetRow(profileID: pid, programID: b.programID, season: season, amount: roundedTo(2, b.amount), note: b.note)
        }
        docs = data.docs.map { d in
            MentalDocRow(id: d.id, profileID: pid, title: d.title, url: d.url.absoluteString, folder: d.folder, kind: d.kind,
                         status: d.status, docUpdatedAt: Timestamp(d.updatedAt), docUpdatedBy: d.updatedBy, note: d.note,
                         visibility: d.visibility)
        }
        lockedDocs = data.lockedDocs.map { LockedMentalDocRow(id: $0.id, profileID: pid, folder: $0.folder, docUpdatedAt: Timestamp($0.updatedAt)) }
        access = data.access
        bodyMeasurements = data.bodyMeasurements.compactMap { BodyMeasurementRow($0, profileID: pid) }
        wallballDrills = data.wallballDrills.enumerated().map { WallballDrillRow($1, profileID: pid, sortOrder: $0) }
        wallballSessions = data.wallballSessions.map { WallballBundle($0, profileID: pid) }
    }

    // MARK: - Rows → app data

    /// The profile's data rebuilt from rows, sorted the way the app lists things.
    public var appData: AppData {
        let p = profile
        let athlete = AthleteProfile(firstName: p.firstName, classYear: p.classYear, positions: p.positions, benchmarkGroup: p.benchmarkGroup,
                                     mentalCoachName: p.mentalCoachName, weeklyGoalHours: p.weeklyGoalHours, season: p.seasonLabel,
                                     bodyUnits: p.bodyUnits, usdToCAD: p.usdToCAD)
        return AppData(
            id: p.id,
            profile: athlete,
            programs: programs.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.map { r in
                Program(id: r.id, name: r.name, detail: r.detail, group: r.programGroup, sessionCategory: r.sessionCategory, monogram: r.monogram,
                        firstSeason: r.firstSeason, lastSeason: r.lastSeason)
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
                Expense(id: r.id, date: r.spentAt.date, title: r.title, category: r.category, amount: r.amount, note: r.note,
                        programID: r.programID, season: r.season, tripID: r.tripID, currency: r.currency, originalAmount: r.originalAmount)
            },
            docs: docs.sorted { $0.docUpdatedAt > $1.docUpdatedAt }.compactMap { r in
                URL(string: r.url).map {
                    MentalDoc(id: r.id, title: r.title, url: $0, folder: r.folder, kind: r.kind, status: r.status,
                              updatedAt: r.docUpdatedAt.date, updatedBy: r.docUpdatedBy, note: r.note, visibility: r.visibility)
                }
            },
            bodyMeasurements: bodyMeasurements.sorted { $0.measuredAt < $1.measuredAt }.map { r in
                BodyMeasurement(id: r.id, date: r.measuredAt.date, heightCm: r.heightCm, weightKg: r.weightKg, note: r.note)
            },
            wallballDrills: wallballDrills.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }.map { r in
                WallballDrill(id: r.id, name: r.name, detail: r.detail, hands: r.hands, defaultReps: r.defaultReps, isHidden: r.hidden)
            },
            wallballSessions: wallballSessions.sorted { $0.session.doneAt < $1.session.doneAt }.map { b in
                WallballSession(id: b.session.id, date: b.session.doneAt.date,
                                sets: b.sets.sorted { $0.position < $1.position }.map { WallballSet(drillID: $0.drillID, hand: $0.hand, reps: $0.reps) },
                                minutes: b.session.minutes, challengeSeconds: b.session.challengeSeconds, notes: b.session.notes)
            },
            themeID: p.themeID,
            // profiles.season_budget is still written for older builds, but the budgets per season are what count.
            seasonBudgets: seasonBudgets.sorted { $0.season < $1.season }.map { SeasonBudget(season: $0.season, amount: $0.amount, note: $0.note) },
            programBudgets: programBudgets.sorted { ($0.season, $0.programID) < ($1.season, $1.programID) }.map {
                ProgramBudget(programID: $0.programID, season: $0.season, amount: $0.amount, note: $0.note)
            },
            trips: trips.sorted { ($0.departsAt, $0.id.uuidString) < ($1.departsAt, $1.id.uuidString) }.map { r in
                Trip(id: r.id, name: r.name, destination: r.destination, country: r.country, departureDate: r.departsAt.date,
                     returnDate: r.returnsAt.date, season: r.season, programID: r.programID, eventID: r.eventID, budget: r.budget,
                     travelMode: r.travelMode, travelDetails: r.travelDetails, hotelName: r.hotelName, hotelAddress: r.hotelAddress,
                     hotelConfirmation: r.hotelConfirmation, hotelCheckIn: r.hotelCheckIn?.date, hotelCheckOut: r.hotelCheckOut?.date,
                     note: r.note)
            },
            lockedDocs: lockedDocs.sorted { $0.docUpdatedAt > $1.docUpdatedAt }.map {
                LockedMentalDoc(id: $0.id, folder: $0.folder, updatedAt: $0.docUpdatedAt.date)
            },
            access: access
        )
    }
}

/// A season the database accepts (2000/01 to 2100/01), or nil.
private func validSeason(_ season: Int) -> Int? {
    (2000...2100).contains(season) ? season : nil
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
            && Set(bodyMeasurements) == Set(other.bodyMeasurements)
            && Set(wallballDrills) == Set(other.wallballDrills) && Set(wallballSessions) == Set(other.wallballSessions)
            && Set(seasonBudgets) == Set(other.seasonBudgets) && Set(programBudgets) == Set(other.programBudgets)
            && Set(trips) == Set(other.trips) && Set(lockedDocs) == Set(other.lockedDocs) && access == other.access
    }
}

// MARK: - Coaches

/// A coach's roster (`rosters`). Made, renamed and given new codes through functions; the coach reads their own.
public struct RosterRow: Decodable, Hashable, Identifiable, Sendable {
    public static let table = "rosters"

    public var id: UUID
    public var kind: RosterKind
    public var name: String
    public var joinCode: String?

    public init(id: UUID, kind: RosterKind, name: String, joinCode: String?) {
        self.id = id
        self.kind = kind
        self.name = name
        self.joinCode = joinCode
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name
        case joinCode = "join_code"
    }
}

/// An athlete on a roster (`roster_athletes`).
public struct RosterAthleteRow: Decodable, Hashable, Sendable {
    public static let table = "roster_athletes"

    public var rosterID: UUID
    public var profileID: UUID

    enum CodingKeys: String, CodingKey {
        case rosterID = "roster_id", profileID = "profile_id"
    }
}

/// An athlete on the signed-in coach's rosters (`roster_athlete_profiles`): what a coach sees of the profile.
public struct CoachAthleteProfileRow: Decodable, Hashable, Sendable {
    public static let table = "roster_athlete_profiles"

    public var id: UUID
    public var firstName: String
    public var classYear: Int?
    public var positions: String
    public var benchmarkGroup: BenchmarkGroup?
    public var weeklyGoalHours: Double
    public var themeID: String

    enum CodingKeys: String, CodingKey {
        case id, positions
        case firstName = "first_name", classYear = "class_year", benchmarkGroup = "benchmark_group"
        case weeklyGoalHours = "weekly_goal_hours", themeID = "theme_id"
    }

    /// As a profile row, with blanks for what coaches don't see.
    var profileRow: ProfileRow {
        ProfileRow(id: id, firstName: firstName, classYear: classYear, positions: positions, benchmarkGroup: benchmarkGroup,
                   mentalCoachName: "", weeklyGoalHours: weeklyGoalHours, seasonLabel: "", seasonBudget: 0, themeID: themeID,
                   bodyUnits: .imperial, usdToCAD: ExchangeRate.defaultUSDToCAD)
    }
}

/// A coach on an athlete, from `athlete_coaches`, for the family's People list.
public struct AthleteCoachRow: Decodable, Hashable, Identifiable, Sendable {
    public var rosterID: UUID
    public var rosterName: String
    public var kind: RosterKind
    public var coachID: UUID
    public var coachName: String
    /// The signed-in account (the athlete's login) lets this coach open the docs it locked.
    public var canOpenLocked: Bool

    public var id: UUID { rosterID }

    public var displayName: String {
        let name = coachName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "A coach" : name
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case rosterID = "roster_id", rosterName = "roster_name", coachID = "coach_id", coachName = "coach_name",
             canOpenLocked = "can_open_locked"
    }
}

/// What a code someone was given is for (`describe_code`).
public enum CodeInfo: Equatable, Sendable, Decodable {
    /// An invite to link this account to an athlete.
    case invite(athleteName: String, relationship: Relationship)
    /// A coach's roster to add an athlete to.
    case roster(name: String, kind: RosterKind, coachName: String)

    private enum CodingKeys: String, CodingKey {
        case type, athlete, relationship, roster, kind, coach
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "invite":
            self = .invite(athleteName: try c.decode(String.self, forKey: .athlete),
                           relationship: try c.decode(Relationship.self, forKey: .relationship))
        case "roster":
            self = .roster(name: try c.decode(String.self, forKey: .roster), kind: try c.decode(RosterKind.self, forKey: .kind),
                           coachName: try c.decode(String.self, forKey: .coach))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown code type \(other)")
        }
    }
}
