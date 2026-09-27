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
}

/// Everything the app stores, saved as one JSON file on the device.
public struct AppData: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

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
    /// True while the app is showing the built-in sample season.
    public var isSample: Bool

    public init(profile: AthleteProfile, programs: [Program], sessions: [TrainingSession] = [], combineResults: [CombineResult] = [], events: [SeasonEvent] = [], expenses: [Expense] = [], seasonBudget: Double = 0, docs: [MentalDoc] = [], themeID: String = ThemeCatalog.defaultID, isSample: Bool = false) {
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
        self.isSample = isSample
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

    /// A clean season with the same programs and profile, no logged data.
    public func blankSeason() -> AppData {
        var copy = AppData(profile: profile, programs: programs, seasonBudget: seasonBudget, themeID: themeID)
        copy.profile.firstName = profile.firstName
        return copy
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
