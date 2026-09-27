import Foundation

/// Tests in the NDTP (Future Track) physical testing battery.
public enum CombineMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case gripLeft
    case gripRight
    case squatJump
    case countermovementJump
    case sprint10m
    case sprint20m
    case proAgilityLeft
    case proAgilityRight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gripLeft: return "Grip strength · left hand"
        case .gripRight: return "Grip strength · right hand"
        case .squatJump: return "Squat jump"
        case .countermovementJump: return "Countermovement jump"
        case .sprint10m: return "10 m sprint"
        case .sprint20m: return "20 m sprint"
        case .proAgilityLeft: return "Pro agility (5-10-5) · left"
        case .proAgilityRight: return "Pro agility (5-10-5) · right"
        }
    }

    public var shortTitle: String {
        switch self {
        case .gripLeft: return "Grip · left"
        case .gripRight: return "Grip · right"
        case .squatJump: return "Squat jump"
        case .countermovementJump: return "CMJ"
        case .sprint10m: return "10 m sprint"
        case .sprint20m: return "20 m sprint"
        case .proAgilityLeft: return "Pro agility · left"
        case .proAgilityRight: return "Pro agility · right"
        }
    }

    /// The physical quality the test measures.
    public var quality: String {
        switch self {
        case .gripLeft, .gripRight: return "Upper-body strength"
        case .squatJump, .countermovementJump: return "Lower-body explosive power"
        case .sprint10m: return "Linear acceleration"
        case .sprint20m: return "Maximum sprint speed"
        case .proAgilityLeft, .proAgilityRight: return "Change of direction"
        }
    }

    public var unit: String {
        switch self {
        case .gripLeft, .gripRight: return "N"
        case .squatJump, .countermovementJump: return "in"
        case .sprint10m, .sprint20m, .proAgilityLeft, .proAgilityRight: return "s"
        }
    }

    public var lowerIsBetter: Bool {
        switch self {
        case .sprint10m, .sprint20m, .proAgilityLeft, .proAgilityRight: return true
        default: return false
        }
    }

    /// Decimal places used when showing a result.
    public var decimals: Int {
        switch self {
        case .gripLeft, .gripRight: return 0
        case .squatJump, .countermovementJump: return 1
        case .sprint10m, .sprint20m: return 3
        case .proAgilityLeft, .proAgilityRight: return 2
        }
    }

    /// Which row of the standards table the metric is judged against.
    public var standard: StandardTest {
        switch self {
        case .gripLeft, .gripRight: return .grip
        case .squatJump: return .squatJump
        case .countermovementJump: return .countermovementJump
        case .sprint10m: return .sprint10m
        case .sprint20m: return .sprint20m
        case .proAgilityLeft, .proAgilityRight: return .proAgility
        }
    }

    /// Scale used to draw the tier band, worse → better (left → right).
    public var bandRange: (worse: Double, better: Double) {
        switch self {
        case .gripLeft, .gripRight: return (200, 600)
        case .squatJump, .countermovementJump: return (7, 18)
        case .sprint10m: return (2.20, 1.70)
        case .sprint20m: return (3.80, 2.95)
        case .proAgilityLeft, .proAgilityRight: return (5.40, 4.40)
        }
    }

    /// Decimal places the standards guide uses for cut-offs.
    public var thresholdDecimals: Int {
        switch self {
        case .gripLeft, .gripRight: return 0
        case .squatJump, .countermovementJump: return 1
        default: return 2
        }
    }

    public func format(_ value: Double, withUnit: Bool = true) -> String {
        format(value, decimals: decimals, withUnit: withUnit)
    }

    public func formatThreshold(_ value: Double) -> String {
        format(value, decimals: thresholdDecimals, withUnit: true)
    }

    private func format(_ value: Double, decimals: Int, withUnit: Bool) -> String {
        let number = String(format: "%.\(decimals)f", value)
        guard withUnit else { return number }
        return unit == "in" ? "\(number)″" : "\(number) \(unit)"
    }
}

/// Rows in the NDTP standards tables.
public enum StandardTest: String, Codable, CaseIterable, Sendable {
    case grip
    case squatJump
    case countermovementJump
    case sprint10m
    case sprint20m
    case proAgility
}

/// Age and gender groups in the NDTP standards guide.
public enum BenchmarkGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case u15Women
    case u17Women
    case u19Women
    case u15Men
    case u17Men
    case u19Men

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .u15Women: return "U15 Women"
        case .u17Women: return "U17 Women"
        case .u19Women: return "U19 Women"
        case .u15Men: return "U15 Men"
        case .u17Men: return "U17 Men"
        case .u19Men: return "U19 Men"
        }
    }

    /// The next age group up, used for the "at the next level" comparison.
    public var next: BenchmarkGroup? {
        switch self {
        case .u15Women: return .u17Women
        case .u17Women: return .u19Women
        case .u15Men: return .u17Men
        case .u17Men: return .u19Men
        case .u19Women, .u19Men: return nil
        }
    }
}

public enum Tier: Int, Codable, Comparable, CaseIterable, Sendable {
    case developing = 0
    case competitive = 1
    case elite = 2

    public var title: String {
        switch self {
        case .developing: return "Developing"
        case .competitive: return "Competitive"
        case .elite: return "Elite"
        }
    }

    public var next: Tier? { Tier(rawValue: rawValue + 1) }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Cut-offs for one test in one group.
///
/// For higher-is-better tests a result is Competitive at `competitive` or above and Elite at `elite` or above.
/// For lower-is-better (timed) tests a result is Competitive at `competitive` or below and Elite below `elite`.
public struct TierThresholds: Equatable, Sendable {
    public var competitive: Double
    public var elite: Double

    public init(competitive: Double, elite: Double) {
        self.competitive = competitive
        self.elite = elite
    }
}

/// Where a single result sits and how far it is from the next tier.
public struct TierAssessment: Equatable, Sendable {
    public var tier: Tier
    public var nextTier: Tier?
    /// Amount still needed to reach `nextTier`, in the metric's unit. Nil when already Elite.
    public var gapToNextTier: Double?
    /// How far past the Elite line the result is, when Elite.
    public var marginPastElite: Double?
    public var thresholds: TierThresholds
}

/// NDTP 2026 Fitness Standards Guide — Future Track Physical Performance Standards, version 1.0 (July 2026).
public enum NDTPStandards {
    public static let source = "NDTP 2026 Fitness Standards Guide v1.0 (July 2026)"

    private static let table: [BenchmarkGroup: [StandardTest: TierThresholds]] = [
        .u15Women: [
            .grip: .init(competitive: 280, elite: 307),
            .squatJump: .init(competitive: 9.0, elite: 10.7),
            .countermovementJump: .init(competitive: 10.0, elite: 11.9),
            .sprint10m: .init(competitive: 2.00, elite: 1.92),
            .proAgility: .init(competitive: 5.10, elite: 4.92)
        ],
        .u17Women: [
            .grip: .init(competitive: 298, elite: 329),
            .squatJump: .init(competitive: 9.8, elite: 10.7),
            .countermovementJump: .init(competitive: 10.6, elite: 11.9),
            .sprint10m: .init(competitive: 2.02, elite: 1.94),
            .proAgility: .init(competitive: 5.04, elite: 4.86)
        ],
        .u19Women: [
            .grip: .init(competitive: 271, elite: 329),
            .squatJump: .init(competitive: 9.8, elite: 11.0),
            .countermovementJump: .init(competitive: 10.8, elite: 12.6),
            .sprint10m: .init(competitive: 1.99, elite: 1.92),
            .proAgility: .init(competitive: 4.96, elite: 4.85)
        ],
        .u15Men: [
            .grip: .init(competitive: 320, elite: 458),
            .squatJump: .init(competitive: 10.5, elite: 12.5),
            .countermovementJump: .init(competitive: 10.7, elite: 12.7),
            .sprint10m: .init(competitive: 2.09, elite: 1.96),
            .sprint20m: .init(competitive: 3.64, elite: 3.37),
            .proAgility: .init(competitive: 5.15, elite: 4.93)
        ],
        .u17Men: [
            .grip: .init(competitive: 485, elite: 556),
            .squatJump: .init(competitive: 14.0, elite: 15.9),
            .countermovementJump: .init(competitive: 14.6, elite: 16.1),
            .sprint10m: .init(competitive: 1.87, elite: 1.78),
            .sprint20m: .init(competitive: 3.16, elite: 3.06),
            .proAgility: .init(competitive: 4.74, elite: 4.60)
        ],
        .u19Men: [
            .grip: .init(competitive: 507, elite: 565),
            .squatJump: .init(competitive: 14.7, elite: 16.5),
            .countermovementJump: .init(competitive: 15.0, elite: 17.2),
            .sprint10m: .init(competitive: 1.90, elite: 1.81),
            .sprint20m: .init(competitive: 3.19, elite: 3.07),
            .proAgility: .init(competitive: 4.73, elite: 4.55)
        ]
    ]

    /// Tiny tolerance so results typed to the same precision as a cut-off land on the right side of it.
    private static let epsilon = 1e-9

    public static func thresholds(for metric: CombineMetric, in group: BenchmarkGroup) -> TierThresholds? {
        table[group]?[metric.standard]
    }

    public static func tier(for value: Double, metric: CombineMetric, group: BenchmarkGroup) -> Tier? {
        guard let t = thresholds(for: metric, in: group) else { return nil }
        if metric.lowerIsBetter {
            if value < t.elite - epsilon { return .elite }
            if value <= t.competitive + epsilon { return .competitive }
            return .developing
        } else {
            if value >= t.elite - epsilon { return .elite }
            if value >= t.competitive - epsilon { return .competitive }
            return .developing
        }
    }

    public static func assess(_ value: Double, metric: CombineMetric, group: BenchmarkGroup) -> TierAssessment? {
        guard let t = thresholds(for: metric, in: group), let tier = tier(for: value, metric: metric, group: group) else { return nil }
        switch tier {
        case .elite:
            let margin = metric.lowerIsBetter ? t.elite - value : value - t.elite
            return TierAssessment(tier: .elite, nextTier: nil, gapToNextTier: nil, marginPastElite: max(margin, 0), thresholds: t)
        case .competitive:
            let gap = metric.lowerIsBetter ? value - t.elite : t.elite - value
            return TierAssessment(tier: .competitive, nextTier: .elite, gapToNextTier: max(gap, 0), marginPastElite: nil, thresholds: t)
        case .developing:
            let gap = metric.lowerIsBetter ? value - t.competitive : t.competitive - value
            return TierAssessment(tier: .developing, nextTier: .competitive, gapToNextTier: max(gap, 0), marginPastElite: nil, thresholds: t)
        }
    }

    /// Plain-language gap line, e.g. "15 N to Elite (307 N+)" or "0.02 s under the Elite line (4.92 s)".
    public static func gapDescription(_ value: Double, metric: CombineMetric, group: BenchmarkGroup) -> String? {
        guard let a = assess(value, metric: metric, group: group) else { return nil }
        let t = a.thresholds
        let cut: (Double) -> String = { metric.formatThreshold($0) }
        if let margin = a.marginPastElite {
            if margin < 0.0005 { return "Right on the Elite line (\(cut(t.elite)))" }
            let word = metric.lowerIsBetter ? "under" : "above"
            return "\(metric.format(margin)) \(word) the Elite line (\(cut(t.elite)))"
        }
        guard let gap = a.gapToNextTier, let next = a.nextTier else { return nil }
        let target = next == .elite ? t.elite : t.competitive
        if metric.lowerIsBetter {
            let bound = next == .elite ? "under \(cut(target))" : cut(target)
            return "\(metric.format(gap)) off \(next.title) (\(bound))"
        }
        return "\(metric.format(gap)) to \(next.title) (\(cut(target))+)"
    }
}

/// One measured value from a testing day.
public struct CombineMeasurement: Codable, Hashable, Sendable {
    public var metric: CombineMetric
    public var value: Double

    public init(metric: CombineMetric, value: Double) {
        self.metric = metric
        self.value = value
    }
}

/// A full testing day (baseline, re-test, …).
public struct CombineResult: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var event: String
    public var measurements: [CombineMeasurement]
    public var heightText: String
    public var weightText: String
    public var isSample: Bool

    public init(id: UUID = UUID(), date: Date, event: String, measurements: [CombineMeasurement], heightText: String = "", weightText: String = "", isSample: Bool = false) {
        self.id = id
        self.date = date
        self.event = event
        self.measurements = measurements
        self.heightText = heightText
        self.weightText = weightText
        self.isSample = isSample
    }

    public func value(for metric: CombineMetric) -> Double? {
        measurements.first { $0.metric == metric }?.value
    }

    /// Count of results in each tier for a group.
    public func tierCounts(in group: BenchmarkGroup) -> [Tier: Int] {
        var counts: [Tier: Int] = [.developing: 0, .competitive: 0, .elite: 0]
        for m in measurements {
            if let tier = NDTPStandards.tier(for: m.value, metric: m.metric, group: group) {
                counts[tier, default: 0] += 1
            }
        }
        return counts
    }
}
