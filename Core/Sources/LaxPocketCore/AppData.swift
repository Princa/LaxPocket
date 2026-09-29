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

    public init(firstName: String, classYear: Int?, positions: String, benchmarkGroup: BenchmarkGroup, mentalCoachName: String = "", weeklyGoalHours: Double = 12, season: String) {
        self.firstName = firstName
        self.classYear = classYear
        self.positions = positions
        self.benchmarkGroup = benchmarkGroup
        self.mentalCoachName = mentalCoachName
        self.weeklyGoalHours = weeklyGoalHours
        self.season = season
    }

    /// "Olivia's Season" style title.
    public var seasonTitle: String {
        let name = firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "My Season" : "\(name)’s Season"
    }

    /// The season a date falls in. Seasons start in August, so Sep 2026 → "2026/27" and Mar 2027 → "2026/27".
    public static func seasonLabel(for date: Date, calendar: Calendar = .laxWeek) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let start = month >= 8 ? year : year - 1
        return String(format: "%d/%02d", start, (start + 1) % 100)
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
    public var expenses: [Expense]
    public var seasonBudget: Double
    public var docs: [MentalDoc]
    public var themeID: String

    public init(id: UUID = UUID(), profile: AthleteProfile, programs: [Program] = [], sessions: [TrainingSession] = [], combineResults: [CombineResult] = [], events: [SeasonEvent] = [], expenses: [Expense] = [], seasonBudget: Double = 0, docs: [MentalDoc] = [], themeID: String = ThemeCatalog.defaultID) {
        self.id = id
        self.schemaVersion = AppData.currentSchemaVersion
        self.profile = profile
        self.programs = programs
        self.sessions = sessions
        self.combineResults = combineResults
        self.events = events
        self.expenses = expenses
        self.seasonBudget = seasonBudget
        self.docs = docs
        self.themeID = themeID
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, profile, programs, sessions, combineResults, events, expenses, seasonBudget, docs, themeID
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
        seasonBudget = try c.decodeIfPresent(Double.self, forKey: .seasonBudget) ?? 0
        docs = try c.decodeIfPresent([MentalDoc].self, forKey: .docs) ?? []
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? ThemeCatalog.defaultID
    }

    /// A new, empty profile for an athlete.
    /// - Parameter clubs: clubs and teams the athlete plays for, e.g. ("Club 2031", "Club team"). Blank names are skipped.
    public static func newProfile(_ profile: AthleteProfile, themeID: String = ThemeCatalog.defaultID,
                                  clubs: [(name: String, detail: String)] = []) -> AppData {
        let programs = clubs.compactMap { club -> Program? in
            let name = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return Program.club(name: name, detail: club.detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return AppData(profile: profile, programs: programs, themeID: themeID)
    }

    /// The clubs and teams the athlete plays for: programs in the Teams & leagues group.
    public var clubs: [Program] {
        programs.filter { $0.group == .teams }
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

    /// A clean season for the same athlete: keeps the profile, programs, budget and theme, drops logged data.
    public func blankSeason() -> AppData {
        AppData(id: id, profile: profile, programs: programs, seasonBudget: seasonBudget, themeID: themeID)
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
