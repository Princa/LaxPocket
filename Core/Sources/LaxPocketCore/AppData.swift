import Foundation

public struct AthleteProfile: Codable, Hashable, Sendable {
    public var firstName: String
    public var classYear: Int?
    public var positions: String
    public var benchmarkGroup: BenchmarkGroup
    public var mentalCoachName: String
    public var weeklyGoalHours: Double
    /// Season label, e.g. "2026/27".
    public var season: String
    /// How height and weight are shown and typed in.
    public var bodyUnits: BodyUnits
    /// Canadian dollars per US dollar, for expenses paid in US dollars and for showing the budget in US dollars.
    public var usdToCAD: Double

    public init(firstName: String, classYear: Int?, positions: String, benchmarkGroup: BenchmarkGroup, mentalCoachName: String = "", weeklyGoalHours: Double = 12, season: String,
                bodyUnits: BodyUnits = .imperial, usdToCAD: Double = ExchangeRate.defaultUSDToCAD) {
        self.firstName = firstName
        self.classYear = classYear
        self.positions = positions
        self.benchmarkGroup = benchmarkGroup
        self.mentalCoachName = mentalCoachName
        self.weeklyGoalHours = weeklyGoalHours
        self.season = season
        self.bodyUnits = bodyUnits
        self.usdToCAD = usdToCAD
    }

    private enum CodingKeys: String, CodingKey {
        case firstName, classYear, positions, benchmarkGroup, mentalCoachName, weeklyGoalHours, season, bodyUnits, usdToCAD
    }

    /// Profiles saved before height and weight tracking have no `bodyUnits`, and those saved before currencies have no
    /// `usdToCAD`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try c.decode(String.self, forKey: .firstName)
        classYear = try c.decodeIfPresent(Int.self, forKey: .classYear)
        positions = try c.decode(String.self, forKey: .positions)
        benchmarkGroup = try c.decode(BenchmarkGroup.self, forKey: .benchmarkGroup)
        mentalCoachName = try c.decode(String.self, forKey: .mentalCoachName)
        weeklyGoalHours = try c.decode(Double.self, forKey: .weeklyGoalHours)
        season = try c.decode(String.self, forKey: .season)
        bodyUnits = try c.decodeIfPresent(BodyUnits.self, forKey: .bodyUnits) ?? .imperial
        usdToCAD = try c.decodeIfPresent(Double.self, forKey: .usdToCAD) ?? ExchangeRate.defaultUSDToCAD
    }

    /// "Olivia's Season" style title.
    public var seasonTitle: String {
        let name = firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "My Season" : "\(name)’s Season"
    }

    /// The season a date falls in. Seasons start in August, so Sep 2026 → "2026/27" and Mar 2027 → "2026/27".
    public static func seasonLabel(for date: Date, calendar: Calendar = .laxWeek) -> String {
        seasonLabel(start: seasonStart(for: date, calendar: calendar))
    }

    /// The season a date falls in, as the year it starts: Sep 2026 → 2026, Mar 2027 → 2026.
    public static func seasonStart(for date: Date, calendar: Calendar = .laxWeek) -> Int {
        let year = calendar.component(.year, from: date)
        return calendar.component(.month, from: date) >= 8 ? year : year - 1
    }

    /// 2026 → "2026/27".
    public static func seasonLabel(start: Int) -> String {
        String(format: "%d/%02d", start, (start + 1) % 100)
    }

    /// The year a season label starts with: "2026/27" or "2026-2027" → 2026. Nil when it doesn't start with a year.
    public static func seasonStart(label: String) -> Int? {
        let digits = label.trimmingCharacters(in: .whitespaces).prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isNumber), let year = Int(digits), (2000...2100).contains(year) else { return nil }
        return year
    }

    /// The season this profile is set to, as the year it starts; the season of `now` if the label isn't a year.
    public func currentSeason(now: Date = Date()) -> Int {
        AthleteProfile.seasonStart(label: season) ?? AthleteProfile.seasonStart(for: now)
    }
}

/// Everything stored for one athlete profile, saved as its own JSON file on the device.
public struct AppData: Codable, Equatable, Sendable {
    /// 1: single season file with a sample season. 2: one file per athlete profile.
    public static let currentSchemaVersion = 2

    /// The athlete profile's ID. Also the profile's ID in the cloud.
    public var id: UUID
    public var schemaVersion: Int
    public var profile: AthleteProfile
    public var programs: [Program]
    public var sessions: [TrainingSession]
    public var combineResults: [CombineResult]
    public var events: [SeasonEvent]
    /// Every season's expenses; each one says which season it counts toward.
    public var expenses: [Expense]
    /// The overall budget for each season that has one.
    public var seasonBudgets: [SeasonBudget]
    /// What's set aside for each program, per season.
    public var programBudgets: [ProgramBudget]
    /// Tournament, showcase and camp trips; their expenses say which trip they're for.
    public var trips: [Trip]
    public var docs: [MentalDoc]
    /// Height and weight checks. They belong to the athlete, so a blank season keeps them.
    public var bodyMeasurements: [BodyMeasurement]
    /// Drills the athlete added, and built-in drills the athlete changed. Built-ins left as they are aren't stored.
    public var wallballDrills: [WallballDrill]
    public var wallballSessions: [WallballSession]
    public var themeID: String

    public init(id: UUID = UUID(), profile: AthleteProfile, programs: [Program] = [], sessions: [TrainingSession] = [], combineResults: [CombineResult] = [], events: [SeasonEvent] = [], expenses: [Expense] = [], seasonBudget: Double = 0, docs: [MentalDoc] = [], bodyMeasurements: [BodyMeasurement] = [],
                wallballDrills: [WallballDrill] = [], wallballSessions: [WallballSession] = [], themeID: String = ThemeCatalog.defaultID,
                seasonBudgets: [SeasonBudget] = [], programBudgets: [ProgramBudget] = [], trips: [Trip] = []) {
        self.id = id
        self.schemaVersion = AppData.currentSchemaVersion
        self.profile = profile
        self.programs = programs
        self.sessions = sessions
        self.combineResults = combineResults
        self.events = events
        self.expenses = expenses
        self.seasonBudgets = seasonBudgets
        self.programBudgets = programBudgets
        self.trips = trips
        self.docs = docs
        self.bodyMeasurements = bodyMeasurements
        self.wallballDrills = wallballDrills
        self.wallballSessions = wallballSessions
        self.themeID = themeID
        // `seasonBudget` is the current season's overall budget.
        if seasonBudget > 0 { self.seasonBudget = seasonBudget }
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, profile, programs, sessions, combineResults, events, expenses, seasonBudgets, programBudgets, trips, docs,
             bodyMeasurements, wallballDrills, wallballSessions, themeID
    }

    /// Files saved before budgets per season had one `seasonBudget` for the season the profile was set to.
    private enum LegacyKeys: String, CodingKey {
        case seasonBudget
    }

    /// Reads current files and version 1 season files, which had no `id`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        schemaVersion = AppData.currentSchemaVersion
        profile = try c.decode(AthleteProfile.self, forKey: .profile)
        programs = try c.decodeIfPresent([Program].self, forKey: .programs) ?? []
        sessions = try c.decodeIfPresent([TrainingSession].self, forKey: .sessions) ?? []
        combineResults = try c.decodeIfPresent([CombineResult].self, forKey: .combineResults) ?? []
        events = try c.decodeIfPresent([SeasonEvent].self, forKey: .events) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        programBudgets = try c.decodeIfPresent([ProgramBudget].self, forKey: .programBudgets) ?? []
        trips = try c.decodeIfPresent([Trip].self, forKey: .trips) ?? []
        if let budgets = try c.decodeIfPresent([SeasonBudget].self, forKey: .seasonBudgets) {
            seasonBudgets = budgets
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Double.self, forKey: .seasonBudget) ?? 0
            seasonBudgets = legacy > 0 ? [SeasonBudget(season: profile.currentSeason(), amount: legacy)] : []
        }
        docs = try c.decodeIfPresent([MentalDoc].self, forKey: .docs) ?? []
        bodyMeasurements = try c.decodeIfPresent([BodyMeasurement].self, forKey: .bodyMeasurements) ?? []
        wallballDrills = try c.decodeIfPresent([WallballDrill].self, forKey: .wallballDrills) ?? []
        wallballSessions = try c.decodeIfPresent([WallballSession].self, forKey: .wallballSessions) ?? []
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? ThemeCatalog.defaultID
    }

    /// A new, empty profile for an athlete.
    public static func newProfile(_ profile: AthleteProfile, themeID: String = ThemeCatalog.defaultID) -> AppData {
        AppData(profile: profile, themeID: themeID)
    }

    /// Stand-in shown while no profile exists yet. Never saved.
    public static let placeholder = AppData(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        profile: AthleteProfile(firstName: "", classYear: nil, positions: "", benchmarkGroup: .u15Women, season: AthleteProfile.seasonLabel(for: Date()))
    )

    /// Name and theme, for the profile list.
    public var summary: ProfileSummary {
        ProfileSummary(id: id, name: profile.firstName, themeID: themeID)
    }

    public func program(id: String) -> Program? {
        programs.first { $0.id == id }
    }

    /// Latest testing day, if any.
    public var latestCombine: CombineResult? {
        combineResults.max { $0.date < $1.date }
    }

    /// Every wall ball drill: the built-in routine with the athlete's changes, then the athlete's own drills.
    public var wallballLibrary: [WallballDrill] {
        WallballCatalog.library(wallballDrills)
    }

    public func wallballDrill(id: String) -> WallballDrill? {
        wallballDrills.first { $0.id == id } ?? WallballCatalog.builtIn(id: id)
    }

    /// Hours logged with each program across the season.
    public var hoursByProgram: [String: Double] {
        var totals: [String: Double] = [:]
        for session in sessions { totals[session.programID, default: 0] += session.hours }
        return totals
    }

    /// Number of sessions logged with each program.
    public var sessionCountByProgram: [String: Int] {
        var counts: [String: Int] = [:]
        for session in sessions { counts[session.programID, default: 0] += 1 }
        return counts
    }

    /// A clean season for the same athlete: keeps the profile, programs, budgets, trips and expenses (each belongs to a
    /// season), height and weight history, wall ball drills and theme, drops the season's logged data. Trips lose their
    /// link to the events that go.
    public func blankSeason() -> AppData {
        AppData(id: id, profile: profile, programs: programs, expenses: expenses, bodyMeasurements: bodyMeasurements,
                wallballDrills: wallballDrills, themeID: themeID, seasonBudgets: seasonBudgets, programBudgets: programBudgets,
                trips: trips.map { var trip = $0; trip.eventID = nil; return trip })
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
