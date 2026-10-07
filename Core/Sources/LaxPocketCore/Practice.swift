import Foundation

// Home practice for sports without hands to balance: hockey's shooting, stickhandling and passing. Lacrosse keeps wall
// ball (Wallball.swift). A drill counts shots (optionally how many were on target), minutes or reps, and the dashboard,
// weekly goals, coach view and coach tasks work from that. See docs/multi-sport.md.

/// What a drill trains. Groups drills on screen and in the reports.
public enum PracticeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shooting
    case stickhandling
    case passing
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shooting: return "Shooting"
        case .stickhandling: return "Stickhandling"
        case .passing: return "Passing"
        case .other: return "Other"
        }
    }

    /// What a timed challenge counts for a drill of this kind: "shots", "touches", "passes", "reps".
    public var challengeNoun: String {
        switch self {
        case .shooting: return "shots"
        case .stickhandling: return "touches"
        case .passing: return "passes"
        case .other: return "reps"
        }
    }
}

/// How a drill is counted.
public enum PracticeMeasure: String, Codable, CaseIterable, Identifiable, Sendable {
    case shots
    case minutes
    case reps

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shots: return "Shots"
        case .minutes: return "Minutes"
        case .reps: return "Reps"
        }
    }

    /// "120 shots", "15 min", "40 reps".
    public func format(_ amount: Int) -> String {
        switch self {
        case .shots: return "\(amount.formatted()) shot\(amount == 1 ? "" : "s")"
        case .minutes: return "\(amount) min"
        case .reps: return "\(amount.formatted()) rep\(amount == 1 ? "" : "s")"
        }
    }

    /// Steps the log's steppers move by.
    public var step: Int {
        switch self {
        case .shots, .reps: return 5
        case .minutes: return 1
        }
    }
}

/// One practice drill: a built-in from `PracticeCatalog`, or one the athlete added.
public struct PracticeDrill: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// How to do it, in a line.
    public var detail: String
    public var kind: PracticeKind
    public var measure: PracticeMeasure
    /// Shooting drills can also count how many shots were on target.
    public var tracksTarget: Bool
    /// Suggested when the drill is picked: shots, minutes or reps.
    public var defaultAmount: Int
    /// Hidden drills keep their history but aren't offered for new sessions.
    public var isHidden: Bool

    public init(id: String = PracticeDrill.newID(), name: String, detail: String = "", kind: PracticeKind, measure: PracticeMeasure,
                tracksTarget: Bool = false, defaultAmount: Int, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.detail = detail
        self.kind = kind
        self.measure = measure
        self.tracksTarget = tracksTarget && measure == .shots
        self.defaultAmount = defaultAmount
        self.isHidden = isHidden
    }

    /// Amounts a drill can suggest. The database checks the same range.
    public static let defaultAmountRange = 1...500

    /// A fresh ID for a drill added in the app. Built-in IDs are words, so they never clash.
    public static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    public var isBuiltIn: Bool { PracticeCatalog.builtInIDs.contains(id) }
}

/// The drills each sport starts with.
public enum PracticeCatalog {
    /// The built-in backhand: the shot the shot-mix check looks at.
    public static let backhandID = "backhand"

    public static let hockey: [PracticeDrill] = [
        PracticeDrill(id: "wrist-shot", name: "Wrist shot", detail: "Puck at the heel, sweep and roll the wrists, follow through to the target.",
                      kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 50),
        PracticeDrill(id: "snap-shot", name: "Snap shot", detail: "Short pull back, quick snap, release before the goalie sets.",
                      kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 25),
        PracticeDrill(id: backhandID, name: "Backhand", detail: "Cup the puck on the backhand, lift with the bottom hand, finish high.",
                      kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 25),
        PracticeDrill(id: "slap-shot", name: "Slap shot", detail: "Weight on the back leg, hit the ice just behind the puck.",
                      kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 15),
        PracticeDrill(id: "one-timer", name: "One-timer", detail: "Off a pass or a rebounder, shoot without stopping the puck.",
                      kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 20),
        PracticeDrill(id: "catch-and-release", name: "Catch and release", detail: "Take the pass and shoot in one motion.",
                      kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 20),
        PracticeDrill(id: "toe-drag-shot", name: "Toe drag and shoot", detail: "Pull in with the toe, change the angle, shoot in the same motion.",
                      kind: .shooting, measure: .shots, tracksTarget: true, defaultAmount: 20),
        PracticeDrill(id: "wide-dribble", name: "Wide dribble", detail: "Far forehand to far backhand, arms away from the body.",
                      kind: .stickhandling, measure: .minutes, defaultAmount: 3),
        PracticeDrill(id: "quick-hands", name: "Quick hands", detail: "Narrow, fast taps in front of the toes.",
                      kind: .stickhandling, measure: .minutes, defaultAmount: 3),
        PracticeDrill(id: "figure-eights", name: "Figure eights", detail: "Around two pucks or cones, both directions.",
                      kind: .stickhandling, measure: .minutes, defaultAmount: 3),
        PracticeDrill(id: "toe-drags", name: "Toe drags", detail: "Pull across with the toe of the blade, push back out.",
                      kind: .stickhandling, measure: .minutes, defaultAmount: 2),
        PracticeDrill(id: "top-hand-only", name: "Top hand only", detail: "One hand on the stick, puck close.",
                      kind: .stickhandling, measure: .minutes, defaultAmount: 2),
        PracticeDrill(id: "head-up", name: "Head up", detail: "Stickhandle while reading something across the room.",
                      kind: .stickhandling, measure: .minutes, defaultAmount: 2),
        PracticeDrill(id: "dangle-course", name: "Dangle course", detail: "Through and around cones or a stick on the floor.",
                      kind: .stickhandling, measure: .minutes, defaultAmount: 5),
        PracticeDrill(id: "forehand-pass", name: "Forehand passes", detail: "Against a rebounder, receive and give in one rhythm.",
                      kind: .passing, measure: .reps, defaultAmount: 30),
        PracticeDrill(id: "backhand-pass", name: "Backhand passes", detail: "Cup the puck, sweep it through on the backhand.",
                      kind: .passing, measure: .reps, defaultAmount: 30),
        PracticeDrill(id: "saucer-pass", name: "Saucer passes", detail: "Over a stick, landing flat.",
                      kind: .passing, measure: .reps, defaultAmount: 20)
    ]

    public static let builtInIDs: Set<String> = Set(hockey.map(\.id))

    /// The built-in drills for a sport. Lacrosse has wall ball instead.
    public static func drills(for sport: Sport) -> [PracticeDrill] {
        sport == .hockey ? hockey : []
    }

    public static func builtIn(id: String) -> PracticeDrill? {
        hockey.first { $0.id == id }
    }

    /// Every drill the athlete has: the sport's built-ins in catalog order, with any of the athlete's changes, then the
    /// athlete's own.
    public static func library(_ saved: [PracticeDrill], sport: Sport) -> [PracticeDrill] {
        var byID: [String: PracticeDrill] = [:]
        for drill in saved where byID[drill.id] == nil { byID[drill.id] = drill }
        return drills(for: sport).map { byID[$0.id] ?? $0 } + saved.filter { !builtInIDs.contains($0.id) }
    }
}

/// What was done of one drill in a session: shots, minutes or reps, and for shots, how many were on target if counted.
/// In a timed challenge the amount is the count reached in the time (shots, touches, passes).
public struct PracticeSet: Codable, Hashable, Sendable {
    public var drillID: String
    public var amount: Int
    public var onTarget: Int?

    public init(drillID: String, amount: Int, onTarget: Int? = nil) {
        self.drillID = drillID
        self.amount = amount
        self.onTarget = onTarget
    }

    /// What one set can hold. The database checks the same range.
    public static let amountRange = 1...5000
}

/// A day's practice, or a timed challenge.
public struct PracticeSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    /// One per drill, in the order they were done.
    public var sets: [PracticeSet]
    /// How long it took, if noted.
    public var minutes: Int?
    /// Set for a timed challenge: seconds on the clock for each drill.
    public var challengeSeconds: Int?
    public var notes: String

    public init(id: UUID = UUID(), date: Date, sets: [PracticeSet], minutes: Int? = nil, challengeSeconds: Int? = nil, notes: String = "") {
        self.id = id
        self.date = date
        self.sets = sets
        self.minutes = minutes
        self.challengeSeconds = challengeSeconds
        self.notes = notes
    }

    public var isChallenge: Bool { challengeSeconds != nil }

    /// One set per drill with something in it: repeats are added together, in the order each first appears, and an
    /// on-target count is kept within the shots.
    public static func normalized(_ sets: [PracticeSet]) -> [PracticeSet] {
        var order: [String] = []
        var amounts: [String: Int] = [:]
        var targets: [String: Int] = [:]
        for set in sets where set.amount > 0 {
            if amounts[set.drillID] == nil { order.append(set.drillID) }
            amounts[set.drillID, default: 0] += set.amount
            if let onTarget = set.onTarget { targets[set.drillID, default: 0] += onTarget }
        }
        return order.map { id in
            let amount = min(amounts[id] ?? 0, PracticeSet.amountRange.upperBound)
            return PracticeSet(drillID: id, amount: amount, onTarget: targets[id].map { min(max($0, 0), amount) })
        }
    }
}

/// Shots, minutes and reps added up.
public struct PracticeTotals: Equatable, Sendable {
    public var shots: Int
    /// Shots on target, out of `shotsCounted`.
    public var onTarget: Int
    /// Shots whose on-target count was kept.
    public var shotsCounted: Int
    public var minutes: Double
    public var reps: Int

    public init(shots: Int = 0, onTarget: Int = 0, shotsCounted: Int = 0, minutes: Double = 0, reps: Int = 0) {
        self.shots = shots
        self.onTarget = onTarget
        self.shotsCounted = shotsCounted
        self.minutes = minutes
        self.reps = reps
    }

    public var isEmpty: Bool { shots == 0 && minutes == 0 && reps == 0 }

    /// On target out of the shots counted, 0…1. Nil when none were counted.
    public var accuracy: Double? {
        shotsCounted > 0 ? Double(onTarget) / Double(shotsCounted) : nil
    }

    /// Whole minutes, for goals and tasks.
    public var wholeMinutes: Int { Int(minutes.rounded()) }

    public static func + (a: PracticeTotals, b: PracticeTotals) -> PracticeTotals {
        PracticeTotals(shots: a.shots + b.shots, onTarget: a.onTarget + b.onTarget, shotsCounted: a.shotsCounted + b.shotsCounted,
                       minutes: a.minutes + b.minutes, reps: a.reps + b.reps)
    }

    /// One set of a drill. In a challenge, a minutes drill counts the time on the clock, not the touches.
    static func of(_ set: PracticeSet, drill: PracticeDrill?, challengeSeconds: Int?) -> PracticeTotals {
        switch drill?.measure ?? .reps {
        case .shots:
            let counted = set.onTarget != nil ? set.amount : 0
            return PracticeTotals(shots: set.amount, onTarget: set.onTarget ?? 0, shotsCounted: counted)
        case .minutes:
            return PracticeTotals(minutes: challengeSeconds.map { Double($0) / 60 } ?? Double(set.amount))
        case .reps:
            return PracticeTotals(reps: set.amount)
        }
    }
}

/// Totals for one day or one week.
public struct PracticePeriod: Identifiable, Equatable, Sendable {
    /// Start of the day or week.
    public var start: Date
    public var totals: PracticeTotals

    public init(start: Date, totals: PracticeTotals) {
        self.start = start
        self.totals = totals
    }

    public var id: Date { start }
}

/// Days in a row with something logged, up to today. A streak still counts until a whole day is missed, so it shows
/// yesterday's run in the morning before today's practice is in. Wall ball and practice count streaks the same way.
public enum DailyStreak {
    public static func count(days: Set<Date>, today: Date, calendar: Calendar = .laxWeek) -> Int {
        var day = calendar.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

/// Reports and trends for the practice dashboard, the coach's view and coach tasks.
public enum PracticeStats {
    /// Backhand under this share of the week's shots is called out.
    public static let backhandThreshold = 0.15
    /// Shots in a week before the shot mix is judged.
    public static let shotMixMinimum = 50

    public static func totals(_ sessions: [PracticeSession], library: [PracticeDrill]) -> PracticeTotals {
        let drills = index(library)
        return sessions.reduce(PracticeTotals()) { sum, session in
            session.sets.reduce(sum) { $0 + .of($1, drill: drills[$1.drillID], challengeSeconds: session.challengeSeconds) }
        }
    }

    /// Totals for each kind of drill.
    public static func byKind(_ sessions: [PracticeSession], library: [PracticeDrill]) -> [PracticeKind: PracticeTotals] {
        let drills = index(library)
        var result: [PracticeKind: PracticeTotals] = [:]
        for session in sessions {
            for set in session.sets {
                let drill = drills[set.drillID]
                result[drill?.kind ?? .other, default: PracticeTotals()] = result[drill?.kind ?? .other, default: PracticeTotals()]
                    + .of(set, drill: drill, challengeSeconds: session.challengeSeconds)
            }
        }
        return result
    }

    /// Totals for each drill.
    public static func byDrill(_ sessions: [PracticeSession], library: [PracticeDrill]) -> [String: PracticeTotals] {
        let drills = index(library)
        var result: [String: PracticeTotals] = [:]
        for session in sessions {
            for set in session.sets {
                result[set.drillID, default: PracticeTotals()] = result[set.drillID, default: PracticeTotals()]
                    + .of(set, drill: drills[set.drillID], challengeSeconds: session.challengeSeconds)
            }
        }
        return result
    }

    /// Sessions from `start` up to, not including, `end`.
    public static func sessions(_ sessions: [PracticeSession], from start: Date, to end: Date) -> [PracticeSession] {
        sessions.filter { $0.date >= start && $0.date < end }
    }

    /// Sessions in the Monday-to-Sunday week of `date`.
    public static func sessions(_ sessions: [PracticeSession], inWeekOf date: Date, calendar: Calendar = .laxWeek) -> [PracticeSession] {
        let start = Workload.startOfWeek(for: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return self.sessions(sessions, from: start, to: end)
    }

    /// Totals on each of the `count` days up to and including `day`, oldest first. Days without practice are empty.
    public static func days(endingOn day: Date, count: Int, sessions: [PracticeSession], library: [PracticeDrill],
                            calendar: Calendar = .laxWeek) -> [PracticePeriod] {
        let last = calendar.startOfDay(for: day)
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return (0..<max(count, 0)).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: last).map { start in
                PracticePeriod(start: start, totals: totals(byDay[start] ?? [], library: library))
            }
        }
    }

    /// Totals in each of the `count` Monday-start weeks up to and including the week of `date`, oldest first.
    public static func weeks(endingAt date: Date, count: Int, sessions: [PracticeSession], library: [PracticeDrill],
                             calendar: Calendar = .laxWeek) -> [PracticePeriod] {
        let current = Workload.startOfWeek(for: date, calendar: calendar)
        let byWeek = Dictionary(grouping: sessions) { Workload.startOfWeek(for: $0.date, calendar: calendar) }
        return (0..<max(count, 0)).reversed().compactMap { back in
            calendar.date(byAdding: .weekOfYear, value: -back, to: current).map { start in
                PracticePeriod(start: start, totals: totals(byWeek[start] ?? [], library: library))
            }
        }
    }

    /// Days in a row with practice, up to today. See `DailyStreak`.
    public static func streak(_ sessions: [PracticeSession], today: Date, calendar: Calendar = .laxWeek) -> Int {
        let days = Set(sessions.filter { $0.sets.contains { $0.amount > 0 } }.map { calendar.startOfDay(for: $0.date) })
        return DailyStreak.count(days: days, today: today, calendar: calendar)
    }

    /// The day with the most shots. Nil with no shots.
    public static func bestShotDay(_ sessions: [PracticeSession], library: [PracticeDrill], calendar: Calendar = .laxWeek) -> PracticePeriod? {
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return byDay.map { PracticePeriod(start: $0.key, totals: totals($0.value, library: library)) }
            .filter { $0.totals.shots > 0 }
            .max { ($0.totals.shots, $1.start) < ($1.totals.shots, $0.start) }
    }

    /// Backhand's share of the shots, 0…1. Nil with no shots.
    public static func backhandShare(_ byDrill: [String: PracticeTotals]) -> Double? {
        let shots = byDrill.values.reduce(0) { $0 + $1.shots }
        guard shots > 0 else { return nil }
        return Double(byDrill[PracticeCatalog.backhandID]?.shots ?? 0) / Double(shots)
    }

    /// True when the backhand is under `backhandThreshold` of at least `shotMixMinimum` shots.
    public static func backhandBehind(_ byDrill: [String: PracticeTotals]) -> Bool {
        let shots = byDrill.values.reduce(0) { $0 + $1.shots }
        guard shots >= shotMixMinimum, let share = backhandShare(byDrill) else { return false }
        return share < backhandThreshold
    }

    /// Where this week's count is heading by Sunday, at the pace so far. Nil before anything is logged.
    public static func pace(_ soFar: Double, now: Date, calendar: Calendar = .laxWeek) -> Double? {
        guard soFar > 0 else { return nil }
        let start = Workload.startOfWeek(for: now, calendar: calendar)
        let days = (calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0) + 1
        return soFar / Double(max(days, 1)) * 7
    }

    /// Challenge lengths that have been done, shortest first.
    public static func challengeLengths(_ sessions: [PracticeSession]) -> [Int] {
        Set(sessions.compactMap(\.challengeSeconds)).sorted()
    }

    /// Best count for each drill across challenges of one length. The earliest wins a tie.
    public static func challengeBests(_ sessions: [PracticeSession], seconds: Int) -> [String: ChallengeBest] {
        var bests: [String: ChallengeBest] = [:]
        for session in sessions where session.challengeSeconds == seconds {
            for set in session.sets {
                let candidate = ChallengeBest(reps: set.amount, date: session.date, sessionID: session.id)
                if let current = bests[set.drillID], (current.reps, candidate.date) >= (candidate.reps, current.date) { continue }
                bests[set.drillID] = candidate
            }
        }
        return bests
    }

    private static func index(_ library: [PracticeDrill]) -> [String: PracticeDrill] {
        var result: [String: PracticeDrill] = [:]
        for drill in library where result[drill.id] == nil { result[drill.id] = drill }
        return result
    }
}

/// Drills and amounts picked for a session before it's saved.
public struct PracticeDraft: Equatable, Sendable {
    /// Amount by drill. A drill is picked while it has an entry.
    public private(set) var amounts: [String: Int] = [:]
    /// Shots on target, for shooting drills that count it. Nil until entered.
    public private(set) var onTarget: [String: Int] = [:]

    public init() {}

    /// The picks in a saved session, to edit it or do it again.
    public init(sets: [PracticeSet]) {
        for set in sets {
            amounts[set.drillID, default: 0] += set.amount
            if let target = set.onTarget { onTarget[set.drillID, default: 0] += target }
        }
    }

    public var isEmpty: Bool { amounts.isEmpty }
    public var pickedCount: Int { amounts.count }

    public func isPicked(_ drillID: String) -> Bool { amounts[drillID] != nil }
    public func amount(_ drillID: String) -> Int { amounts[drillID] ?? 0 }
    public func onTarget(_ drillID: String) -> Int? { onTarget[drillID] }

    /// Picks a drill with `count`, or its default.
    public mutating func pick(_ drill: PracticeDrill, amount count: Int? = nil) {
        amounts[drill.id] = Self.clamped(count ?? drill.defaultAmount)
    }

    public mutating func unpick(_ drillID: String) {
        amounts[drillID] = nil
        onTarget[drillID] = nil
    }

    public mutating func toggle(_ drill: PracticeDrill) {
        if isPicked(drill.id) { unpick(drill.id) } else { pick(drill) }
    }

    /// Picks every drill given, each with its default unless `count` is given. Drills already picked keep theirs.
    public mutating func pickAll(_ drills: [PracticeDrill], amount count: Int? = nil) {
        for drill in drills where !isPicked(drill.id) { pick(drill, amount: count) }
    }

    /// The same amount for every picked drill among `drills` (say, all the shooting ones).
    public mutating func setAll(_ count: Int, in drills: [PracticeDrill]) {
        for drill in drills where isPicked(drill.id) { set(count, drillID: drill.id) }
    }

    public mutating func set(_ count: Int, drillID: String) {
        guard amounts[drillID] != nil else { return }
        amounts[drillID] = Self.clamped(count)
        if let target = onTarget[drillID] { onTarget[drillID] = min(target, amounts[drillID] ?? 0) }
    }

    /// Shots on target for a picked drill; nil stops counting it.
    public mutating func setOnTarget(_ count: Int?, drillID: String) {
        guard let amount = amounts[drillID] else { return }
        onTarget[drillID] = count.map { min(max($0, 0), amount) }
    }

    public mutating func clear() {
        amounts = [:]
        onTarget = [:]
    }

    /// Sets with something in them, in the order of `drills`, then any picked drill not in `drills`.
    public func sets(in drills: [PracticeDrill]) -> [PracticeSet] {
        let known = drills.map(\.id)
        let order = known.filter { amounts[$0] != nil } + amounts.keys.filter { !known.contains($0) }.sorted()
        return order.compactMap { id in
            let amount = amounts[id] ?? 0
            guard amount > 0 else { return nil }
            let tracks = drills.first { $0.id == id }?.tracksTarget ?? false
            return PracticeSet(drillID: id, amount: amount, onTarget: tracks ? onTarget[id].map { min($0, amount) } : nil)
        }
    }

    public func totals(in drills: [PracticeDrill]) -> PracticeTotals {
        PracticeStats.totals([PracticeSession(date: Date(), sets: sets(in: drills))], library: drills)
    }

    static func clamped(_ value: Int) -> Int {
        min(max(value, 0), PracticeSet.amountRange.upperBound)
    }
}

/// A timed practice challenge: each picked drill gets the same time on the clock, and the athlete counts what they did
/// in it (touches, shots, passes).
public enum PracticeChallenge {
    /// Seconds per round offered when setting one up.
    public static let lengths = WallballChallenge.lengths
    public static let defaultLength = WallballChallenge.defaultLength
    /// Countdown before each round.
    public static let getReadySeconds = WallballChallenge.getReadySeconds
    /// Lengths the database accepts.
    public static let secondsRange = WallballChallenge.secondsRange
}

extension AppData {
    /// Every practice drill for this profile's sport: the built-ins with the athlete's changes, then their own.
    public var practiceLibrary: [PracticeDrill] {
        PracticeCatalog.library(practiceDrills, sport: profile.sport)
    }

    public func practiceDrill(id: String) -> PracticeDrill? {
        practiceDrills.first { $0.id == id } ?? PracticeCatalog.builtIn(id: id)
    }
}
