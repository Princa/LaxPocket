import Foundation

/// A coach's roster: a team, or a mental coach's clients. Matches `rosters.kind` in the cloud.
public enum RosterKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case team
    case mental

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .team: return "Team"
        case .mental: return "Mental-game clients"
        }
    }

    /// What a coach on this kind of roster is to the athlete. Mirrors `private.roster_sections` in
    /// supabase/migrations/20261008000000_coach_rosters.sql.
    public var relationship: Relationship {
        switch self {
        case .team: return .coach
        case .mental: return .mentalCoach
        }
    }

    /// What the family is told the coach will see of a lacrosse athlete, before adding them.
    public var sharingSummary: String { sharingSummary(for: .lacrosse) }

    /// What the family is told the coach will see, before adding the athlete. Only the athlete's profile for the roster's
    /// sport, never their other sports.
    public func sharingSummary(for sport: Sport) -> String {
        switch self {
        case .team:
            let training = sport.hasWallball ? "Training, wall ball, combine results"
                : sport.hasPractice ? "Training, shooting and stickhandling, testing" : "Training, testing"
            return "\(training) and events, including reflections. Not mental sessions, mental-game documents, height and weight, the budget, or other sports."
        case .mental:
            return "Training, events and the mental game: mental sessions and shared documents. Not height and weight, the budget, or other sports."
        }
    }
}

/// One of a coach's rosters, with what the coach can see of each athlete on it.
public struct CoachRoster: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: RosterKind
    /// Only athletes' profiles for this sport can join.
    public var sport: Sport
    /// What families enter to add their athlete. Nil when the roster is closed to new athletes.
    public var joinCode: String?
    /// By name.
    public var athletes: [CoachAthlete]
    /// Tasks given on this roster, to everyone or to one athlete. Newest first.
    public var assignments: [Assignment]

    public init(id: UUID, name: String, kind: RosterKind, sport: Sport = .lacrosse, joinCode: String?, athletes: [CoachAthlete],
                assignments: [Assignment] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sport = sport
        self.joinCode = joinCode
        self.athletes = athletes
        self.assignments = assignments
    }

    /// How many of the athletes a task is for have it done for the period that includes `now`, of how many it's for.
    /// Nil when the task isn't running now.
    public func completion(of assignment: Assignment, now: Date, calendar: Calendar = .laxWeek) -> (done: Int, of: Int)? {
        let statuses = athletes.filter { assignment.isFor($0.id) }.compactMap { $0.data.assignmentStatus(assignment, now: now, calendar: calendar) }
        guard assignment.period(containing: now, calendar: calendar) != nil else { return nil }
        return (statuses.filter(\.isDone).count, statuses.count)
    }
}

/// An athlete as their coach sees them: recent weeks of training and home practice (wall ball, or hockey's shooting and
/// stickhandling), recent and upcoming events and, for a
/// mental coach, the mental game. Read from the cloud each time; never saved on the coach's phone.
public struct CoachAthlete: Identifiable, Equatable, Sendable {
    public var data: AppData

    public var id: UUID { data.id }

    public init(data: AppData) {
        self.data = data
    }

    public func week(now: Date, calendar: Calendar = .laxWeek) -> CoachWeek {
        CoachWeek(data, now: now, calendar: calendar)
    }
}

/// How an athlete's week is going, for a row in the coach's roster.
public struct CoachWeek: Equatable, Sendable {
    public enum Flag: Hashable, Sendable {
        /// Well above recent weeks (acute : chronic ratio over 1.5).
        case highLoad
        /// One hand under 40% of the one-handed wall ball reps this week.
        case laggingHand(WallballHand)
        /// Hockey: backhand under 15% of the week's shots.
        case backhandBehind
        /// No training logged for this many days.
        case quiet(days: Int)

        public var title: String {
            switch self {
            case .highLoad: return "Load spike"
            case .laggingHand(let hand): return "\(hand == .left ? "Left" : "Right") hand behind"
            case .backhandBehind: return "Backhand behind"
            case .quiet(let days): return "Nothing logged in \(days) days"
            }
        }
    }

    /// Training this week. Mental hours only count when the coach can see mental sessions.
    public var hours: CategoryHours
    public var goalHours: Double
    /// Acute : chronic ratio from physical hours; nil without earlier weeks to compare with.
    public var loadRatio: Double?
    public var wallball: HandReps
    public var wallballStreak: Int
    /// Hockey practice this week: shots, minutes and reps.
    public var practice: PracticeTotals
    /// Hockey: stickhandling minutes this week.
    public var stickhandlingMinutes: Int
    public var practiceStreak: Int
    public var nextEvent: SeasonEvent?
    public var lastResult: SeasonEvent?
    public var flags: [Flag]

    /// Days without training before a quiet athlete is flagged.
    public static let quietAfterDays = 5

    public var zone: WorkloadZone? { loadRatio.map(Workload.zone(for:)) }

    public var goalFraction: Double { goalHours > 0 ? hours.total / goalHours : 0 }

    public init(_ data: AppData, now: Date, calendar: Calendar = .laxWeek) {
        let week = Workload.sessions(data.sessions, inWeekOf: now, calendar: calendar)
        hours = Workload.hours(for: week)
        goalHours = data.profile.weeklyGoalHours
        let weeks = Workload.weeks(endingAt: now, count: 5, sessions: data.sessions, calendar: calendar)
        loadRatio = Workload.acuteChronicRatio(currentWeekHours: hours.physical, previousWeekHours: weeks.dropLast().map(\.hours.physical))
        let weekStart = Workload.startOfWeek(for: now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        wallball = WallballStats.reps(WallballStats.sessions(data.wallballSessions, from: weekStart, to: weekEnd))
        wallballStreak = WallballStats.streak(data.wallballSessions, today: now, calendar: calendar)
        let library = data.practiceLibrary
        let weekPractice = PracticeStats.sessions(data.practiceSessions, from: weekStart, to: weekEnd)
        practice = PracticeStats.totals(weekPractice, library: library)
        stickhandlingMinutes = PracticeStats.byKind(weekPractice, library: library)[.stickhandling]?.wholeMinutes ?? 0
        practiceStreak = PracticeStats.streak(data.practiceSessions, today: now, calendar: calendar)
        nextEvent = Season.upcoming(data.events, from: now).first
        lastResult = Season.results(data.events).first

        var flags: [Flag] = []
        if loadRatio.map({ $0 > Workload.cautionUpper }) == true { flags.append(.highLoad) }
        if let hand = WallballStats.laggingHand(wallball) { flags.append(.laggingHand(hand)) }
        if PracticeStats.backhandBehind(PracticeStats.byDrill(weekPractice, library: library)) { flags.append(.backhandBehind) }
        let lastSession = data.sessions.filter { $0.date <= now }.map(\.date).max()
        let quietDays = lastSession.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0 }
        if let days = quietDays, days >= CoachWeek.quietAfterDays { flags.append(.quiet(days: days)) }
        self.flags = flags
    }
}

extension CoachRoster {
    /// How far back a coach's view of an athlete reaches: this week and the four before it, for the load ratio.
    public static func since(now: Date, calendar: Calendar = .laxWeek) -> Date {
        let weekStart = Workload.startOfWeek(for: now, calendar: calendar)
        return calendar.date(byAdding: .weekOfYear, value: -4, to: weekStart) ?? weekStart
    }

    /// Events from this long ago show as recent results.
    public static let recentEventDays = 30
}
