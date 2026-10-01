import Foundation

/// Which hand a set of wall ball reps was done with.
public enum WallballHand: String, Codable, CaseIterable, Identifiable, Sendable {
    case right
    case left
    /// A drill that uses both hands at once or switches every rep, counted once.
    case both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .both: return "Both"
        }
    }

    /// One letter for tight spaces: "R", "L", "B".
    public var letter: String { String(title.prefix(1)) }
}

/// How a drill's reps are counted.
public enum DrillHands: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Done with each hand in turn: right and left reps are counted separately.
    case each
    /// Uses both hands at once or switches every rep: one count.
    case together

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .each: return "Right & left"
        case .together: return "Both hands"
        }
    }

    /// The hands a set of this drill is logged for.
    public var hands: [WallballHand] {
        switch self {
        case .each: return [.right, .left]
        case .together: return [.both]
        }
    }
}

/// One wall ball drill: a built-in from `WallballCatalog`, or one the athlete added.
public struct WallballDrill: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// How to do it, in a line.
    public var detail: String
    public var hands: DrillHands
    /// Reps per hand suggested when the drill is picked.
    public var defaultReps: Int
    /// Hidden drills keep their history but aren't offered for new sessions.
    public var isHidden: Bool

    public init(id: String = WallballDrill.newID(), name: String, detail: String = "", hands: DrillHands = .each,
                defaultReps: Int = WallballDrill.standardReps, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.detail = detail
        self.hands = hands
        self.defaultReps = defaultReps
        self.isHidden = isHidden
    }

    public static let standardReps = 25
    /// Reps per hand a drill can suggest. The database checks the same range.
    public static let defaultRepsRange = 1...500

    /// A fresh ID for a drill added in the app. Built-in IDs are words, so they never clash.
    public static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    public var isBuiltIn: Bool { WallballCatalog.builtInIDs.contains(id) }
}

/// The wall ball routine every athlete starts with.
public enum WallballCatalog {
    public static let drills: [WallballDrill] = [
        WallballDrill(id: "overhand", name: "Overhand", detail: "Hands apart, stick by the ear. Catch and throw in one rhythm.", defaultReps: 50),
        WallballDrill(id: "quick-sticks", name: "Quick sticks", detail: "Close to the wall. Catch and release without cradling.", defaultReps: 50),
        WallballDrill(id: "one-handed", name: "One-handed", detail: "Top hand only, choked up near the head."),
        WallballDrill(id: "cross-hand", name: "Cross-hand", detail: "Throw from the opposite side of the body."),
        WallballDrill(id: "sidearm", name: "Sidearm", detail: "Stick parallel to the ground, release at the hip."),
        WallballDrill(id: "behind-the-back", name: "Behind the back", detail: "Release behind the head, catch in front.", defaultReps: 20),
        WallballDrill(id: "underhand", name: "Underhand", detail: "Shovel throw from below the hip.", defaultReps: 20),
        WallballDrill(id: "fake-and-throw", name: "Fake and throw", detail: "Catch, pump fake, then throw.", defaultReps: 20),
        WallballDrill(id: "catch-across-face", name: "Catch across the face", detail: "Catch on the off-stick side, bring it back, throw.", defaultReps: 20),
        WallballDrill(id: "cradle-and-throw", name: "Cradle and throw", detail: "Catch, two cradles, throw.", defaultReps: 20),
        WallballDrill(id: "bounce-catch", name: "Bounce catches", detail: "Throw low so it comes back on a hop.", defaultReps: 20),
        WallballDrill(id: "ground-balls", name: "Ground balls", detail: "Roll it off the wall, scoop through, protect, throw.", defaultReps: 20),
        WallballDrill(id: "long-throws", name: "Long throws", detail: "From 10 m or more, full overhand motion.", defaultReps: 20),
        WallballDrill(id: "switch-hands", name: "Catch and switch", detail: "Catch right, switch to left, throw; then back again.",
                      hands: .together, defaultReps: 30),
        WallballDrill(id: "quick-stick-switch", name: "Alternating quick sticks", detail: "Quick sticks, switching hands every catch.",
                      hands: .together, defaultReps: 30)
    ]

    public static let builtInIDs: Set<String> = Set(drills.map(\.id))

    public static func builtIn(id: String) -> WallballDrill? {
        drills.first { $0.id == id }
    }

    /// Every drill the athlete has: the built-ins in routine order, with any of the athlete's changes, then the athlete's own.
    public static func library(_ saved: [WallballDrill]) -> [WallballDrill] {
        var byID: [String: WallballDrill] = [:]
        for drill in saved where byID[drill.id] == nil { byID[drill.id] = drill }
        return drills.map { byID[$0.id] ?? $0 } + saved.filter { !builtInIDs.contains($0.id) }
    }
}

/// Reps of one drill with one hand.
public struct WallballSet: Codable, Hashable, Sendable {
    public var drillID: String
    public var hand: WallballHand
    public var reps: Int

    public init(drillID: String, hand: WallballHand, reps: Int) {
        self.drillID = drillID
        self.hand = hand
        self.reps = reps
    }

    /// Reps one set can hold. The database checks the same range.
    public static let repsRange = 1...5000

    public var key: DrillHand { DrillHand(drillID: drillID, hand: hand) }
}

/// A drill done with one hand: one set in a session, or one round of a challenge.
public struct DrillHand: Hashable, Sendable {
    public var drillID: String
    public var hand: WallballHand

    public init(drillID: String, hand: WallballHand) {
        self.drillID = drillID
        self.hand = hand
    }
}

/// A day's wall ball, or a timed challenge.
public struct WallballSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    /// One per drill and hand, in the order they were done.
    public var sets: [WallballSet]
    /// How long it took, if noted.
    public var minutes: Int?
    /// Set for a timed challenge: seconds on the clock for each drill and hand.
    public var challengeSeconds: Int?
    public var notes: String

    public init(id: UUID = UUID(), date: Date, sets: [WallballSet], minutes: Int? = nil, challengeSeconds: Int? = nil, notes: String = "") {
        self.id = id
        self.date = date
        self.sets = sets
        self.minutes = minutes
        self.challengeSeconds = challengeSeconds
        self.notes = notes
    }

    public var isChallenge: Bool { challengeSeconds != nil }

    public var reps: HandReps { HandReps(sets) }

    /// Number of different drills done.
    public var drillCount: Int { Set(sets.map(\.drillID)).count }

    /// Sets with reps, one per drill and hand: repeats are added together, in the order each first appears.
    public static func normalized(_ sets: [WallballSet]) -> [WallballSet] {
        var order: [DrillHand] = []
        var totals: [DrillHand: Int] = [:]
        for set in sets where set.reps > 0 {
            if totals[set.key] == nil { order.append(set.key) }
            totals[set.key, default: 0] += set.reps
        }
        return order.map { WallballSet(drillID: $0.drillID, hand: $0.hand, reps: min(totals[$0] ?? 0, WallballSet.repsRange.upperBound)) }
    }
}

/// Reps split by hand.
public struct HandReps: Equatable, Sendable {
    public var right: Int
    public var left: Int
    public var both: Int

    public init(right: Int = 0, left: Int = 0, both: Int = 0) {
        self.right = right
        self.left = left
        self.both = both
    }

    public init<S: Sequence>(_ sets: S) where S.Element == WallballSet {
        self.init()
        for set in sets { add(set.reps, hand: set.hand) }
    }

    public var total: Int { right + left + both }

    public subscript(hand: WallballHand) -> Int {
        switch hand {
        case .right: return right
        case .left: return left
        case .both: return both
        }
    }

    public mutating func add(_ reps: Int, hand: WallballHand) {
        switch hand {
        case .right: right += reps
        case .left: left += reps
        case .both: both += reps
        }
    }

    public static func + (a: HandReps, b: HandReps) -> HandReps {
        HandReps(right: a.right + b.right, left: a.left + b.left, both: a.both + b.both)
    }

    /// Left hand's share of the one-handed reps, 0...1. Nil with no one-handed reps.
    public var leftShare: Double? {
        let oneHanded = right + left
        return oneHanded > 0 ? Double(left) / Double(oneHanded) : nil
    }
}

/// Reps for one day or one week.
public struct PeriodReps: Identifiable, Equatable, Sendable {
    /// Start of the day or week.
    public var start: Date
    public var reps: HandReps

    public init(start: Date, reps: HandReps) {
        self.start = start
        self.reps = reps
    }

    public var id: Date { start }
}

/// The most reps of one drill with one hand in a timed challenge.
public struct ChallengeBest: Equatable, Sendable {
    public var reps: Int
    public var date: Date
    public var sessionID: UUID

    public init(reps: Int, date: Date, sessionID: UUID) {
        self.reps = reps
        self.date = date
        self.sessionID = sessionID
    }
}

/// Reports and trends for the wall ball dashboard.
public enum WallballStats {
    /// One hand under this share of the one-handed reps is called out.
    public static let balanceThreshold = 0.4

    public static func reps(_ sessions: [WallballSession]) -> HandReps {
        HandReps(sessions.lazy.flatMap(\.sets))
    }

    /// Sessions from `start` up to, not including, `end`.
    public static func sessions(_ sessions: [WallballSession], from start: Date, to end: Date) -> [WallballSession] {
        sessions.filter { $0.date >= start && $0.date < end }
    }

    /// Reps on each of the `count` days up to and including `day`, oldest first. Days without wall ball are zero.
    public static func days(endingOn day: Date, count: Int, sessions: [WallballSession], calendar: Calendar = .laxWeek) -> [PeriodReps] {
        let last = calendar.startOfDay(for: day)
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return (0..<max(count, 0)).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: last).map { start in
                PeriodReps(start: start, reps: reps(byDay[start] ?? []))
            }
        }
    }

    /// Reps in each of the `count` Monday-start weeks up to and including the week of `date`, oldest first.
    public static func weeks(endingAt date: Date, count: Int, sessions: [WallballSession], calendar: Calendar = .laxWeek) -> [PeriodReps] {
        let current = Workload.startOfWeek(for: date, calendar: calendar)
        let byWeek = Dictionary(grouping: sessions) { Workload.startOfWeek(for: $0.date, calendar: calendar) }
        return (0..<max(count, 0)).reversed().compactMap { back in
            calendar.date(byAdding: .weekOfYear, value: -back, to: current).map { start in
                PeriodReps(start: start, reps: reps(byWeek[start] ?? []))
            }
        }
    }

    /// Days in a row with wall ball, up to today. A streak still counts until a whole day is missed,
    /// so it shows yesterday's run in the morning before today's reps are in.
    public static func streak(_ sessions: [WallballSession], today: Date, calendar: Calendar = .laxWeek) -> Int {
        let days = Set(sessions.filter { $0.reps.total > 0 }.map { calendar.startOfDay(for: $0.date) })
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

    /// The day with the most reps. Nil with no reps.
    public static func bestDay(_ sessions: [WallballSession], calendar: Calendar = .laxWeek) -> PeriodReps? {
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return byDay.map { PeriodReps(start: $0.key, reps: reps($0.value)) }
            .filter { $0.reps.total > 0 }
            .max { ($0.reps.total, $1.start) < ($1.reps.total, $0.start) }
    }

    /// Reps by drill.
    public static func byDrill(_ sessions: [WallballSession]) -> [String: HandReps] {
        var totals: [String: HandReps] = [:]
        for set in sessions.lazy.flatMap(\.sets) {
            totals[set.drillID, default: HandReps()].add(set.reps, hand: set.hand)
        }
        return totals
    }

    /// The hand that's falling behind, when one gets under `balanceThreshold` of the one-handed reps.
    public static func laggingHand(_ reps: HandReps) -> WallballHand? {
        guard let left = reps.leftShare, reps.right + reps.left >= 20 else { return nil }
        if left < balanceThreshold { return .left }
        if 1 - left < balanceThreshold { return .right }
        return nil
    }

    /// Challenge lengths that have been done, shortest first.
    public static func challengeLengths(_ sessions: [WallballSession]) -> [Int] {
        Set(sessions.compactMap(\.challengeSeconds)).sorted()
    }

    /// Best reps for each drill and hand across challenges of one length. The earliest wins a tie.
    public static func challengeBests(_ sessions: [WallballSession], seconds: Int) -> [DrillHand: ChallengeBest] {
        var bests: [DrillHand: ChallengeBest] = [:]
        for session in sessions where session.challengeSeconds == seconds {
            for set in session.sets {
                let candidate = ChallengeBest(reps: set.reps, date: session.date, sessionID: session.id)
                if let current = bests[set.key], (current.reps, candidate.date) >= (candidate.reps, current.date) { continue }
                bests[set.key] = candidate
            }
        }
        return bests
    }
}

/// Drills and reps picked for a session before it is saved.
public struct WallballDraft: Equatable, Sendable {
    /// Reps by drill and hand. A drill is picked while it has an entry; a hand at 0 is skipped.
    public private(set) var reps: [String: [WallballHand: Int]] = [:]

    public init() {}

    /// The picks in a saved session, to edit it or do it again.
    public init(sets: [WallballSet]) {
        for set in sets { reps[set.drillID, default: [:]][set.hand, default: 0] += set.reps }
    }

    public var isEmpty: Bool { reps.isEmpty }
    public var pickedCount: Int { reps.count }

    public func isPicked(_ drillID: String) -> Bool { reps[drillID] != nil }

    public func reps(_ drillID: String, _ hand: WallballHand) -> Int { reps[drillID]?[hand] ?? 0 }

    /// Picks a drill with `count` reps for each of its hands, or its default.
    public mutating func pick(_ drill: WallballDrill, reps count: Int? = nil) {
        let value = Self.clamped(count ?? drill.defaultReps)
        reps[drill.id] = Dictionary(uniqueKeysWithValues: drill.hands.hands.map { ($0, value) })
    }

    public mutating func unpick(_ drillID: String) {
        reps[drillID] = nil
    }

    public mutating func toggle(_ drill: WallballDrill) {
        if isPicked(drill.id) { unpick(drill.id) } else { pick(drill) }
    }

    /// Picks every drill, each with its default reps unless `count` is given. Drills already picked keep their reps.
    public mutating func pickAll(_ drills: [WallballDrill], reps count: Int? = nil) {
        for drill in drills where !isPicked(drill.id) { pick(drill, reps: count) }
    }

    public mutating func clear() {
        reps = [:]
    }

    /// The same reps for every hand of every picked drill.
    public mutating func setAll(_ count: Int) {
        let value = Self.clamped(count)
        for (drill, hands) in reps {
            reps[drill] = hands.mapValues { _ in value }
        }
    }

    public mutating func set(_ count: Int, drillID: String, hand: WallballHand) {
        guard reps[drillID] != nil else { return }
        reps[drillID]?[hand] = Self.clamped(count)
    }

    /// Sets with reps, in the order of `drills` (right before left), then any picked drill not in `drills`.
    public func sets(in drills: [WallballDrill]) -> [WallballSet] {
        let known = drills.map(\.id)
        let order = known.filter { reps[$0] != nil } + reps.keys.filter { !known.contains($0) }.sorted()
        return order.flatMap { id in
            WallballHand.allCases.compactMap { hand in
                let value = reps[id]?[hand] ?? 0
                return value > 0 ? WallballSet(drillID: id, hand: hand, reps: value) : nil
            }
        }
    }

    public func total(in drills: [WallballDrill]) -> HandReps {
        HandReps(sets(in: drills))
    }

    static func clamped(_ value: Int) -> Int {
        min(max(value, 0), WallballSet.repsRange.upperBound)
    }
}

/// A timed wall ball challenge: each picked drill and hand gets the same time on the clock.
public enum WallballChallenge {
    /// Which hands one-handed drills are done with.
    public enum Hands: String, CaseIterable, Identifiable, Sendable {
        case rightAndLeft
        case right
        case left

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .rightAndLeft: return "Right & left"
            case .right: return "Right only"
            case .left: return "Left only"
            }
        }
    }

    /// Seconds per round offered when setting one up.
    public static let lengths = [30, 45, 60, 90, 120]
    public static let defaultLength = 30
    /// Countdown before each round.
    public static let getReadySeconds = 3
    /// Lengths the database accepts.
    public static let secondsRange = 5...3600

    /// One round per drill and hand, in drill order. Both-hands drills get one round whatever `hands` is.
    public static func rounds(_ drills: [WallballDrill], hands: Hands) -> [DrillHand] {
        drills.flatMap { drill -> [DrillHand] in
            let picked: [WallballHand]
            switch (drill.hands, hands) {
            case (.together, _): picked = [.both]
            case (.each, .rightAndLeft): picked = [.right, .left]
            case (.each, .right): picked = [.right]
            case (.each, .left): picked = [.left]
            }
            return picked.map { DrillHand(drillID: drill.id, hand: $0) }
        }
    }

    /// "30 sec", "1 min", "1 min 30 sec".
    public static func lengthText(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        switch (m, s) {
        case (0, _): return "\(s) sec"
        case (_, 0): return "\(m) min"
        default: return "\(m) min \(s) sec"
        }
    }
}
