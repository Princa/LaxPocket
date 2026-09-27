import Foundation

public enum EventKind: String, Codable, CaseIterable, Sendable {
    case game
    case tournament
    case showcase
    case camp

    public var title: String {
        switch self {
        case .game: return "Game"
        case .tournament: return "Tournament"
        case .showcase: return "Showcase"
        case .camp: return "Camp"
        }
    }
}

public struct GameStats: Codable, Hashable, Sendable {
    public var goals: Int
    public var assists: Int
    public var shots: Int
    public var groundBalls: Int
    public var drawControls: Int
    public var causedTurnovers: Int

    public init(goals: Int = 0, assists: Int = 0, shots: Int = 0, groundBalls: Int = 0, drawControls: Int = 0, causedTurnovers: Int = 0) {
        self.goals = goals
        self.assists = assists
        self.shots = shots
        self.groundBalls = groundBalls
        self.drawControls = drawControls
        self.causedTurnovers = causedTurnovers
    }

    /// Goals ÷ shots, or nil with no shots.
    public var shootingPercentage: Double? {
        shots > 0 ? Double(goals) / Double(shots) : nil
    }

    /// Compact line used in lists, e.g. "2G · 1A · 4GB · 3DC".
    public var summaryLine: String {
        "\(goals)G · \(assists)A · \(groundBalls)GB · \(drawControls)DC"
    }

    public static func + (lhs: GameStats, rhs: GameStats) -> GameStats {
        GameStats(
            goals: lhs.goals + rhs.goals,
            assists: lhs.assists + rhs.assists,
            shots: lhs.shots + rhs.shots,
            groundBalls: lhs.groundBalls + rhs.groundBalls,
            drawControls: lhs.drawControls + rhs.drawControls,
            causedTurnovers: lhs.causedTurnovers + rhs.causedTurnovers
        )
    }
}

public enum FocusOutcome: String, Codable, CaseIterable, Sendable {
    case pending
    case hit
    case partly
    case missed

    public var title: String {
        switch self {
        case .pending: return "—"
        case .hit: return "Hit"
        case .partly: return "Partly"
        case .missed: return "Missed"
        }
    }
}

/// A pre-game goal and how it went.
public struct FocusGoal: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var outcome: FocusOutcome
    public var note: String

    public init(id: UUID = UUID(), text: String, outcome: FocusOutcome = .pending, note: String = "") {
        self.id = id
        self.text = text
        self.outcome = outcome
        self.note = note
    }
}

public struct Reflection: Codable, Hashable, Sendable {
    public var selfRating: Int?
    public var wentWell: String
    public var workOn: String
    public var coachFeedback: String
    public var coachFeedbackDate: Date?

    public init(selfRating: Int? = nil, wentWell: String = "", workOn: String = "", coachFeedback: String = "", coachFeedbackDate: Date? = nil) {
        self.selfRating = selfRating
        self.wentWell = wentWell
        self.workOn = workOn
        self.coachFeedback = coachFeedback
        self.coachFeedbackDate = coachFeedbackDate
    }
}

public struct VideoLink: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var durationText: String

    public init(id: UUID = UUID(), title: String, url: URL, durationText: String = "") {
        self.id = id
        self.title = title
        self.url = url
        self.durationText = durationText
    }
}

public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var done: Bool

    public init(id: UUID = UUID(), title: String, done: Bool = false) {
        self.id = id
        self.title = title
        self.done = done
    }
}

public enum GameOutcome: String, Sendable {
    case win
    case loss
    case tie

    public var letter: String {
        switch self {
        case .win: return "W"
        case .loss: return "L"
        case .tie: return "T"
        }
    }
}

/// A game, tournament, showcase or camp on the season calendar.
public struct SeasonEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: EventKind
    public var title: String
    /// Team or program the event is with, e.g. "SilverMaple League".
    public var team: String
    public var opponent: String?
    public var date: Date
    public var endDate: Date?
    /// When true, only the month is known ("dates TBC").
    public var dateIsTentative: Bool
    public var location: String
    public var ourScore: Int?
    public var theirScore: Int?
    public var stats: GameStats?
    public var focus: [FocusGoal]
    public var reflection: Reflection?
    public var videos: [VideoLink]
    public var checklist: [ChecklistItem]

    public init(
        id: UUID = UUID(), kind: EventKind, title: String, team: String, opponent: String? = nil,
        date: Date, endDate: Date? = nil, dateIsTentative: Bool = false, location: String = "",
        ourScore: Int? = nil, theirScore: Int? = nil, stats: GameStats? = nil,
        focus: [FocusGoal] = [], reflection: Reflection? = nil, videos: [VideoLink] = [], checklist: [ChecklistItem] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.team = team
        self.opponent = opponent
        self.date = date
        self.endDate = endDate
        self.dateIsTentative = dateIsTentative
        self.location = location
        self.ourScore = ourScore
        self.theirScore = theirScore
        self.stats = stats
        self.focus = focus
        self.reflection = reflection
        self.videos = videos
        self.checklist = checklist
    }

    public var hasResult: Bool { ourScore != nil && theirScore != nil }

    public var outcome: GameOutcome? {
        guard let us = ourScore, let them = theirScore else { return nil }
        if us > them { return .win }
        if us < them { return .loss }
        return .tie
    }

    public var scoreLine: String? {
        guard let us = ourScore, let them = theirScore else { return nil }
        return "\(us)–\(them)"
    }

    public var checklistProgress: (done: Int, total: Int) {
        (checklist.filter(\.done).count, checklist.count)
    }
}

public struct SeasonRecord: Equatable, Sendable {
    public var wins: Int
    public var losses: Int
    public var ties: Int
    public var totals: GameStats

    public var gamesPlayed: Int { wins + losses + ties }
    public var line: String { "\(wins)–\(losses)–\(ties)" }
}

public enum Season {
    public static func record(for events: [SeasonEvent]) -> SeasonRecord {
        var record = SeasonRecord(wins: 0, losses: 0, ties: 0, totals: GameStats())
        for event in events {
            switch event.outcome {
            case .win: record.wins += 1
            case .loss: record.losses += 1
            case .tie: record.ties += 1
            case nil: continue
            }
            if let stats = event.stats { record.totals = record.totals + stats }
        }
        return record
    }

    public static func upcoming(_ events: [SeasonEvent], from date: Date) -> [SeasonEvent] {
        events.filter { !$0.hasResult && ($0.endDate ?? $0.date) >= date }.sorted { $0.date < $1.date }
    }

    public static func results(_ events: [SeasonEvent]) -> [SeasonEvent] {
        events.filter(\.hasResult).sorted { $0.date > $1.date }
    }
}
