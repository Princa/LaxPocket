import Foundation

/// How an athlete's height and weight are shown and typed in. Values are always stored in centimetres and kilograms.
public enum BodyUnits: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Feet and inches, pounds.
    case imperial
    /// Centimetres, kilograms.
    case metric

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .imperial: return "Feet, inches & pounds"
        case .metric: return "Centimetres & kilograms"
        }
    }

    /// Short label for segmented pickers.
    public var shortTitle: String {
        switch self {
        case .imperial: return "ft · lb"
        case .metric: return "cm · kg"
        }
    }

    public var heightUnit: String { self == .imperial ? "in" : "cm" }
    public var weightUnit: String { self == .imperial ? "lb" : "kg" }

    public static let centimetresPerInch = 2.54
    public static let kilogramsPerPound = 0.453_592_37

    // MARK: - Conversions

    /// A height in this system's unit: total inches, or centimetres.
    public func height(fromCentimetres cm: Double) -> Double {
        self == .imperial ? cm / Self.centimetresPerInch : cm
    }

    /// A weight in this system's unit: pounds, or kilograms.
    public func weight(fromKilograms kg: Double) -> Double {
        self == .imperial ? kg / Self.kilogramsPerPound : kg
    }

    /// Centimetres, to the 0.1 cm that is stored, from a height in this system's unit.
    public func centimetres(fromHeight value: Double) -> Double {
        BodyMeasurement.roundedHeight(self == .imperial ? value * Self.centimetresPerInch : value)
    }

    /// Kilograms, to the 0.01 kg that is stored, from a weight in this system's unit.
    public func kilograms(fromWeight value: Double) -> Double {
        BodyMeasurement.roundedWeight(self == .imperial ? value * Self.kilogramsPerPound : value)
    }

    /// Whole feet and the inches left over, to 0.1 in: 162.6 cm → (5, 4).
    public static func feetAndInches(fromCentimetres cm: Double) -> (feet: Int, inches: Double) {
        let tenths = Int((cm / centimetresPerInch * 10).rounded())
        return (tenths / 120, Double(tenths % 120) / 10)
    }

    // MARK: - Formatting

    /// "5′4″" or "5′4.5″"; "162.6 cm".
    public func formatHeight(_ cm: Double) -> String {
        guard self == .imperial else { return "\(Self.number(cm)) cm" }
        let parts = Self.feetAndInches(fromCentimetres: cm)
        return "\(parts.feet)′\(Self.number(parts.inches))″"
    }

    /// "112 lb" or "112.5 lb"; "50.8 kg".
    public func formatWeight(_ kg: Double) -> String {
        "\(Self.number(weight(fromKilograms: kg))) \(weightUnit)"
    }

    /// A change in height, e.g. "+0.8 in" or "−2.1 cm".
    public func formatHeightChange(_ cm: Double) -> String {
        "\(Self.signed(height(fromCentimetres: cm))) \(heightUnit)"
    }

    /// A change in weight, e.g. "+3.5 lb" or "−1.2 kg".
    public func formatWeightChange(_ kg: Double) -> String {
        "\(Self.signed(weight(fromKilograms: kg))) \(weightUnit)"
    }

    /// Growth per year, e.g. "2.8 in/yr" or "7.2 cm/yr".
    public func formatGrowthRate(_ cmPerYear: Double) -> String {
        "\(Self.number(height(fromCentimetres: cmPerYear))) \(heightUnit)/yr"
    }

    /// Up to `decimals` places without trailing zeros: 112 → "112", 112.46 → "112.5".
    public static func number(_ value: Double, decimals: Int = 1) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// "+0.8", "−0.8" or "0".
    static func signed(_ value: Double) -> String {
        let text = number(abs(value))
        guard text != "0" else { return text }
        return (value > 0 ? "+" : "−") + text
    }

    /// A number typed with a dot or a comma, e.g. "4,5". Nil when blank or not a number.
    public static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }
}

/// One height and weight check. Either can be left out, e.g. a weigh-in without a height.
public struct BodyMeasurement: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    /// Centimetres, whatever units the athlete uses.
    public var heightCm: Double?
    /// Kilograms, whatever units the athlete uses.
    public var weightKg: Double?
    public var note: String

    public init(id: UUID = UUID(), date: Date, heightCm: Double? = nil, weightKg: Double? = nil, note: String = "") {
        self.id = id
        self.date = date
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.note = note
    }

    /// Heights and weights the app accepts. The database checks the same ranges.
    public static let heightRangeCm: ClosedRange<Double> = 50...250
    public static let weightRangeKg: ClosedRange<Double> = 10...250

    /// To the 0.1 cm the database stores.
    public static func roundedHeight(_ cm: Double) -> Double { (cm * 10).rounded() / 10 }

    /// To the 0.01 kg the database stores.
    public static func roundedWeight(_ kg: Double) -> Double { (kg * 100).rounded() / 100 }
}

/// Height and weight as typed into a form, in the athlete's units.
public struct BodyInput: Equatable, Sendable {
    public var units: BodyUnits
    /// Feet. Only used in imperial units.
    public var feet: String
    /// Inches (the part after the feet) or centimetres.
    public var height: String
    /// Pounds or kilograms.
    public var weight: String

    /// What one field holds.
    public enum Field: Equatable, Sendable {
        case blank
        /// Not a number, or outside the range the app accepts.
        case invalid
        /// Centimetres or kilograms.
        case valid(Double)

        public var value: Double? {
            if case .valid(let v) = self { return v }
            return nil
        }
    }

    /// Fields filled in from stored values, or blank.
    public init(units: BodyUnits, heightCm: Double? = nil, weightKg: Double? = nil) {
        self.units = units
        feet = ""
        height = ""
        weight = ""
        if let heightCm {
            if units == .imperial {
                let parts = BodyUnits.feetAndInches(fromCentimetres: heightCm)
                feet = "\(parts.feet)"
                height = BodyUnits.number(parts.inches)
            } else {
                height = BodyUnits.number(heightCm)
            }
        }
        if let weightKg {
            weight = BodyUnits.number(units.weight(fromKilograms: weightKg), decimals: 2)
        }
    }

    public var heightCm: Field {
        let heightBlank = height.trimmingCharacters(in: .whitespaces).isEmpty
        let feetBlank = units == .metric || feet.trimmingCharacters(in: .whitespaces).isEmpty
        if heightBlank && feetBlank { return .blank }
        let typed: Double
        if units == .imperial {
            let typedFeet: Double? = feetBlank ? 0 : BodyUnits.parse(feet)
            let typedInches: Double? = heightBlank ? 0 : BodyUnits.parse(height)
            // Inches past 11 alongside feet are a typo, not a height.
            guard let f = typedFeet, let i = typedInches, f >= 0, i >= 0, feetBlank || i < 12 else { return .invalid }
            typed = f * 12 + i
        } else {
            guard let value = BodyUnits.parse(height) else { return .invalid }
            typed = value
        }
        let cm = units.centimetres(fromHeight: typed)
        return BodyMeasurement.heightRangeCm.contains(cm) ? .valid(cm) : .invalid
    }

    public var weightKg: Field {
        if weight.trimmingCharacters(in: .whitespaces).isEmpty { return .blank }
        guard let typed = BodyUnits.parse(weight) else { return .invalid }
        let kg = units.kilograms(fromWeight: typed)
        return BodyMeasurement.weightRangeKg.contains(kg) ? .valid(kg) : .invalid
    }

    public var isBlank: Bool { heightCm == .blank && weightKg == .blank }
    public var hasError: Bool { heightCm == .invalid || weightKg == .invalid }

    /// The same values rewritten for the other system's fields. A field that doesn't hold a valid value is cleared.
    public func converted(to newUnits: BodyUnits) -> BodyInput {
        BodyInput(units: newUnits, heightCm: heightCm.value, weightKg: weightKg.value)
    }

    /// `entry` with the typed values. A field left as it was filled in keeps the stored value exactly,
    /// so opening and saving an entry never nudges it through a unit conversion.
    public func applied(to entry: BodyMeasurement) -> BodyMeasurement {
        let original = BodyInput(units: units, heightCm: entry.heightCm, weightKg: entry.weightKg)
        var result = entry
        if feet != original.feet || height != original.height { result.heightCm = heightCm.value }
        if weight != original.weight { result.weightKg = weightKg.value }
        return result
    }
}

/// A value at a point in time, for charts and trends.
public struct BodyPoint: Identifiable, Hashable, Sendable {
    /// The measurement's ID.
    public var id: UUID
    public var date: Date
    public var value: Double

    public init(id: UUID, date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

/// How fast the athlete is growing, between two height checks.
public struct GrowthRate: Equatable, Sendable {
    public var cmPerYear: Double
    public var gainedCm: Double
    public var from: Date
    public var to: Date

    public init(cmPerYear: Double, gainedCm: Double, from: Date, to: Date) {
        self.cmPerYear = cmPerYear
        self.gainedCm = gainedCm
        self.from = from
        self.to = to
    }

    public var isSpurtPace: Bool { cmPerYear >= BodyTrends.spurtCmPerYear }
}

public enum BodyTrends {
    /// About 0.6 cm a month. Growing this fast usually means a growth spurt.
    public static let spurtCmPerYear = 7.2
    /// Heights closer together than this are too noisy for a growth rate.
    public static let growthWindowDays = 90

    public static let spurtAdvice = "That’s growth-spurt pace. Coordination can dip for a while and knees and heels can get sore, so keep an eye on jumping and sprint volume and make time for recovery."

    /// Heights in centimetres, oldest first.
    public static func heights(_ entries: [BodyMeasurement]) -> [BodyPoint] {
        entries.sorted { $0.date < $1.date }.compactMap { m in m.heightCm.map { BodyPoint(id: m.id, date: m.date, value: $0) } }
    }

    /// Weights in kilograms, oldest first.
    public static func weights(_ entries: [BodyMeasurement]) -> [BodyPoint] {
        entries.sorted { $0.date < $1.date }.compactMap { m in m.weightKg.map { BodyPoint(id: m.id, date: m.date, value: $0) } }
    }

    /// Points on or after `start`; all of them when `start` is nil.
    public static func points(_ points: [BodyPoint], since start: Date?) -> [BodyPoint] {
        guard let start else { return points }
        return points.filter { $0.date >= start }
    }

    /// Last value minus first. Nil with fewer than two points.
    public static func change(_ points: [BodyPoint]) -> Double? {
        guard points.count > 1, let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }

    /// Height gained per year, from the latest height back to the most recent one at least `growthWindowDays` before it.
    /// Nil until the heights span that long.
    public static func growthRate(_ entries: [BodyMeasurement]) -> GrowthRate? {
        let points = heights(entries)
        guard let latest = points.last else { return nil }
        let cutoff = latest.date.addingTimeInterval(-Double(growthWindowDays) * 86_400)
        guard let earlier = points.last(where: { $0.date <= cutoff }) else { return nil }
        let years = latest.date.timeIntervalSince(earlier.date) / (365.25 * 86_400)
        let gained = latest.value - earlier.value
        return GrowthRate(cmPerYear: gained / years, gainedCm: gained, from: earlier.date, to: latest.date)
    }

    /// Latest height and weight, e.g. "5′4″ · 112 lb". Nil with no measurements.
    public static func summary(_ entries: [BodyMeasurement], units: BodyUnits) -> String? {
        var parts: [String] = []
        if let height = heights(entries).last { parts.append(units.formatHeight(height.value)) }
        if let weight = weights(entries).last { parts.append(units.formatWeight(weight.value)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
