import Foundation

/// Hours split across the three session categories.
public struct CategoryHours: Equatable, Sendable {
    public var team: Double
    public var skills: Double
    public var fitness: Double

    public init(team: Double = 0, skills: Double = 0, fitness: Double = 0) {
        self.team = team
        self.skills = skills
        self.fitness = fitness
    }

    public var total: Double { team + skills + fitness }

    public subscript(category: SessionCategory) -> Double {
        switch category {
        case .team: return team
        case .skills: return skills
        case .fitness: return fitness
        }
    }

    /// Share of the total for a category, 0...1.
    public func share(of category: SessionCategory) -> Double {
        total > 0 ? self[category] / total : 0
    }
}

/// Totals for one Monday-to-Sunday week.
public struct WeekTotals: Identifiable, Equatable, Sendable {
    public var weekStart: Date
    public var hours: CategoryHours
    public var sessionCount: Int
    public var load: Int

    public var id: Date { weekStart }
}

/// Where this week sits relative to recent weeks.
public enum WorkloadZone: String, Sendable {
    case low
    case sweetSpot
    case caution
    case high

    public var title: String {
        switch self {
        case .low: return "Low"
        case .sweetSpot: return "Balanced"
        case .caution: return "Caution"
        case .high: return "High"
        }
    }
}

public enum Workload {
    /// Lower and upper bounds of the gauge drawn in the app.
    public static let gaugeRange: ClosedRange<Double> = 0.5...1.8
    public static let sweetSpot: ClosedRange<Double> = 0.8...1.3
    public static let cautionUpper = 1.5

    public static func startOfWeek(for date: Date, calendar: Calendar = .laxWeek) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public static func hours(for sessions: [TrainingSession]) -> CategoryHours {
        var result = CategoryHours()
        for session in sessions {
            switch session.category {
            case .team: result.team += session.hours
            case .skills: result.skills += session.hours
            case .fitness: result.fitness += session.hours
            }
        }
        return result
    }

    public static func sessions(_ sessions: [TrainingSession], inWeekOf date: Date, calendar: Calendar = .laxWeek) -> [TrainingSession] {
        let start = startOfWeek(for: date, calendar: calendar)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return sessions.filter { $0.date >= start && $0.date < end }
    }

    /// Totals for `count` weeks, oldest first, ending with the week containing `date`.
    public static func weeks(endingAt date: Date, count: Int, sessions: [TrainingSession], calendar: Calendar = .laxWeek) -> [WeekTotals] {
        let currentStart = startOfWeek(for: date, calendar: calendar)
        return (0..<max(count, 0)).reversed().compactMap { offset -> WeekTotals? in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart) else { return nil }
            let inWeek = Self.sessions(sessions, inWeekOf: weekStart, calendar: calendar)
            return WeekTotals(
                weekStart: weekStart,
                hours: hours(for: inWeek),
                sessionCount: inWeek.count,
                load: inWeek.reduce(0) { $0 + $1.load }
            )
        }
    }

    /// Acute : chronic ratio — this week's hours over the average of the previous weeks.
    /// Returns nil when there is no history to compare against.
    public static func acuteChronicRatio(currentWeekHours: Double, previousWeekHours: [Double]) -> Double? {
        guard !previousWeekHours.isEmpty else { return nil }
        let average = previousWeekHours.reduce(0, +) / Double(previousWeekHours.count)
        guard average > 0 else { return nil }
        return currentWeekHours / average
    }

    public static func zone(for ratio: Double) -> WorkloadZone {
        if ratio < sweetSpot.lowerBound { return .low }
        if ratio <= sweetSpot.upperBound { return .sweetSpot }
        if ratio <= cautionUpper { return .caution }
        return .high
    }

    /// A short, plain-language read of the ratio for the Training screen.
    public static func advice(for zone: WorkloadZone) -> String {
        switch zone {
        case .low: return "Lighter than usual. Fine for a recovery week; otherwise build back up gradually."
        case .sweetSpot: return "Inside the sweet spot. Keep at least one full rest day this week."
        case .caution: return "A big jump on recent weeks. Watch sleep and soreness, and keep the next few days lighter."
        case .high: return "Well above recent weeks. Swap a hard session for recovery to lower injury risk."
        }
    }
}
