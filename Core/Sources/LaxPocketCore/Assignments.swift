import Foundation

/// What a coach's task asks for. Matches `assignments.kind` in the cloud.
public enum AssignmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A number of wall ball reps (lacrosse); done once the athlete's wall ball log reaches it.
    case wallball
    /// A number of shots (hockey); done once the athlete's practice log reaches it.
    case shots
    /// Minutes of stickhandling drills (hockey); done once the athlete's practice log reaches it.
    case stickhandling
    /// Minutes of training, of one category or any; done once the logged sessions reach it.
    case training
    /// Anything else (watch game film, a journal prompt); the athlete or a parent ticks it off.
    case check

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wallball: return "Wall ball reps"
        case .shots: return "Shots"
        case .stickhandling: return "Stickhandling minutes"
        case .training: return "Training minutes"
        case .check: return "Tick off"
        }
    }

    /// A count of reps or shots (`targetReps`).
    public var countsReps: Bool { self == .wallball || self == .shots }

    /// A number of minutes (`targetMinutes`).
    public var countsMinutes: Bool { self == .training || self == .stickhandling }

    /// The kinds a coach can give on a roster for this sport: wall ball for lacrosse, shots and stickhandling for
    /// hockey, and training and tick-off for both.
    public static func available(for sport: Sport) -> [AssignmentKind] {
        allCases.filter { kind in
            switch kind {
            case .wallball: return sport.hasWallball
            case .shots, .stickhandling: return sport.hasPractice
            case .training, .check: return true
            }
        }
    }
}

/// How often a task comes round. Matches `assignments.schedule`.
public enum AssignmentSchedule: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Once, by a due date.
    case once
    case daily
    /// Monday to Sunday.
    case weekly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .once: return "Once, by a date"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        }
    }
}

/// A calendar day, as Postgres `date` stores it: "2026-10-05". Days are in the phone's own time zone.
public struct DayKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .laxWeek) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Nil unless the text is `yyyy-MM-dd`.
    public init?(_ text: String) {
        let parts = text.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2], (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The start of the day.
    public func date(calendar: Calendar = .laxWeek) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: DayKey, b: DayKey) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        // PostgREST sends dates as yyyy-MM-dd; take the date part of anything longer.
        guard let key = DayKey(String(text.prefix(10))) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A task a coach gave the athlete (or their whole roster).
public struct Assignment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var rosterID: UUID
    /// Nil: everyone on the roster.
    public var profileID: UUID?
    public var rosterName: String
    public var coachName: String
    public var kind: AssignmentKind
    public var title: String
    public var notes: String
    public var schedule: AssignmentSchedule
    public var startsOn: DayKey
    /// For a one-off task.
    public var dueOn: DayKey?
    /// The last day of a daily or weekly task; nil: ongoing.
    public var endsOn: DayKey?
    public var targetReps: Int?
    public var targetMinutes: Int?
    /// For a training task: only sessions of this category count. Nil: any.
    public var category: SessionCategory?

    public init(id: UUID = UUID(), rosterID: UUID, profileID: UUID? = nil, rosterName: String = "", coachName: String = "",
                kind: AssignmentKind, title: String, notes: String = "", schedule: AssignmentSchedule, startsOn: DayKey,
                dueOn: DayKey? = nil, endsOn: DayKey? = nil, targetReps: Int? = nil, targetMinutes: Int? = nil, category: SessionCategory? = nil) {
        self.id = id
        self.rosterID = rosterID
        self.profileID = profileID
        self.rosterName = rosterName
        self.coachName = coachName
        self.kind = kind
        self.title = title
        self.notes = notes
        self.schedule = schedule
        self.startsOn = startsOn
        self.dueOn = dueOn
        self.endsOn = endsOn
        self.targetReps = targetReps
        self.targetMinutes = targetMinutes
        self.category = category
    }

    /// "200 reps every day", "5 h of skills every week", "Tick off by Fri, Oct 9".
    public func summary(calendar: Calendar = .laxWeek) -> String {
        let what: String
        switch kind {
        case .wallball: what = "\(targetReps ?? 0) wall ball reps"
        case .shots: what = "\((targetReps ?? 0).formatted()) shots"
        case .stickhandling: what = "\(AssignmentStatus.duration(targetMinutes ?? 0)) of stickhandling"
        case .training:
            let minutes = targetMinutes ?? 0
            let amount = minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
            what = category.map { "\(amount) of \($0.title.lowercased())" } ?? "\(amount) of training"
        case .check: what = "Tick off"
        }
        switch schedule {
        case .daily: return "\(what) every day"
        case .weekly: return "\(what) every week"
        case .once:
            let due = dueOn.map { $0.date(calendar: calendar).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? ""
            return "\(what) by \(due)"
        }
    }

    /// True when the task is for this athlete: given to them, or to their whole roster.
    public func isFor(_ profileID: UUID) -> Bool {
        self.profileID == nil || self.profileID == profileID
    }

    /// The day, week or whole span that `date` falls in, and the day that names it in completions. Nil when the
    /// task isn't running then: before it starts, after it ends, or (once) after its due date.
    public func period(containing date: Date, calendar: Calendar = .laxWeek) -> (start: DayKey, interval: DateInterval)? {
        let day = calendar.startOfDay(for: date)
        guard day >= startsOn.date(calendar: calendar) else { return nil }
        switch schedule {
        case .once:
            guard let due = dueOn?.date(calendar: calendar), let end = calendar.date(byAdding: .day, value: 1, to: due), date < end else { return nil }
            return (startsOn, DateInterval(start: startsOn.date(calendar: calendar), end: end))
        case .daily:
            if let last = endsOn, day > last.date(calendar: calendar) { return nil }
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return (DayKey(day, calendar: calendar), DateInterval(start: day, end: end))
        case .weekly:
            if let last = endsOn, day > last.date(calendar: calendar) { return nil }
            let start = Workload.startOfWeek(for: day, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return (DayKey(start, calendar: calendar), DateInterval(start: start, end: end))
        }
    }
}

/// A task marked done by hand for one period (the day, the week's Monday, or a one-off task's start).
public struct AssignmentCompletion: Codable, Hashable, Sendable {
    public var assignmentID: UUID
    public var periodStart: DayKey

    public init(assignmentID: UUID, periodStart: DayKey) {
        self.assignmentID = assignmentID
        self.periodStart = periodStart
    }
}

/// A coach's note on one of the athlete's games.
public struct CoachNote: Codable, Hashable, Sendable {
    public var eventID: UUID
    public var coachID: UUID
    public var coachName: String
    public var note: String
    public var updatedAt: Date

    public init(eventID: UUID, coachID: UUID, coachName: String, note: String, updatedAt: Date) {
        self.eventID = eventID
        self.coachID = coachID
        self.coachName = coachName
        self.note = note
        self.updatedAt = updatedAt
    }
}

/// Where a task stands for the current day, week or one-off span.
public struct AssignmentStatus: Identifiable, Hashable, Sendable {
    public var assignment: Assignment
    public var periodStart: DayKey
    public var period: DateInterval
    /// Reps or minutes logged in the period; nil for a tick-off task.
    public var logged: Int?
    public var target: Int?
    /// Ticked off by hand.
    public var markedDone: Bool

    public var id: UUID { assignment.id }

    /// Reached the target, or ticked off.
    public var isDone: Bool { markedDone || reachedTarget }

    public var reachedTarget: Bool {
        guard let logged, let target else { return false }
        return logged >= target
    }

    /// 0…1, for a progress bar. A tick-off task is 0 or 1.
    public var fraction: Double {
        if isDone { return 1 }
        guard let logged, let target, target > 0 else { return 0 }
        return min(Double(logged) / Double(target), 1)
    }

    /// "120 / 200 reps", "3 h 20 min of 5 h", "Done".
    public var progressText: String {
        switch assignment.kind {
        case .wallball: return "\(logged ?? 0) / \(target ?? 0) reps"
        case .shots: return "\((logged ?? 0).formatted()) / \((target ?? 0).formatted()) shots"
        case .stickhandling: return "\(Self.duration(logged ?? 0)) of \(Self.duration(target ?? 0))"
        case .training: return "\(Self.duration(logged ?? 0)) of \(Self.duration(target ?? 0))"
        case .check: return isDone ? "Done" : "To do"
        }
    }

    /// "45 min", "2 h", "1 h 30 min".
    public static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

extension AppData {
    /// The athlete's tasks that are running now, with how far along each is: wall ball and training from what's
    /// logged, plus anything ticked off by hand. One-off tasks first by due date, then daily, then weekly.
    public func assignmentStatuses(now: Date, calendar: Calendar = .laxWeek) -> [AssignmentStatus] {
        assignments.filter { $0.isFor(id) }.compactMap { assignmentStatus($0, now: now, calendar: calendar) }
            .sorted { a, b in
                let order: [AssignmentSchedule: Int] = [.once: 0, .daily: 1, .weekly: 2]
                return (order[a.assignment.schedule] ?? 3, a.period.end, a.assignment.title) < (order[b.assignment.schedule] ?? 3, b.period.end, b.assignment.title)
            }
    }

    /// Where one task stands now, or nil when it isn't running.
    public func assignmentStatus(_ assignment: Assignment, now: Date, calendar: Calendar = .laxWeek) -> AssignmentStatus? {
        guard let (start, interval) = assignment.period(containing: now, calendar: calendar) else { return nil }
        let logged: Int?
        let target: Int?
        switch assignment.kind {
        case .wallball:
            logged = WallballStats.reps(wallballSessions.filter { interval.contains($0.date) && $0.date < interval.end }).total
            target = assignment.targetReps
        case .shots:
            logged = PracticeStats.totals(practiceSessions.filter { interval.contains($0.date) && $0.date < interval.end },
                                          library: practiceLibrary).shots
            target = assignment.targetReps
        case .stickhandling:
            let inPeriod = practiceSessions.filter { interval.contains($0.date) && $0.date < interval.end }
            logged = PracticeStats.byKind(inPeriod, library: practiceLibrary)[.stickhandling]?.wholeMinutes ?? 0
            target = assignment.targetMinutes
        case .training:
            logged = sessions.filter { interval.contains($0.date) && $0.date < interval.end && (assignment.category == nil || $0.category == assignment.category) }
                .reduce(0) { $0 + $1.minutes }
            target = assignment.targetMinutes
        case .check:
            logged = nil
            target = nil
        }
        let marked = assignmentCompletions.contains { $0.assignmentID == assignment.id && $0.periodStart == start }
        return AssignmentStatus(assignment: assignment, periodStart: start, period: interval, logged: logged, target: target, markedDone: marked)
    }

    /// Ticks a task off for its current period, or unticks it.
    public mutating func setAssignment(_ id: UUID, done: Bool, periodStart: DayKey) {
        assignmentCompletions.removeAll { $0.assignmentID == id && $0.periodStart == periodStart }
        if done { assignmentCompletions.append(AssignmentCompletion(assignmentID: id, periodStart: periodStart)) }
    }

    /// Coaches' notes on an event, newest first.
    public func coachNotes(for eventID: UUID) -> [CoachNote] {
        coachNotes.filter { $0.eventID == eventID }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
