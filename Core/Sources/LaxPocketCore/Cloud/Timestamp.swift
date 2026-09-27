import Foundation

/// A point in time at millisecond precision, written as ISO 8601 in UTC.
///
/// Postgres `timestamptz` keeps microseconds and PostgREST returns strings like
/// `2026-09-27T15:31:52.925+00:00`. Comparing whole milliseconds means a value that went
/// to the server and back is equal to the one that was sent, which the sync merge relies on.
public struct Timestamp: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var milliseconds: Int64

    public init(milliseconds: Int64) {
        self.milliseconds = milliseconds
    }

    public init(_ date: Date) {
        milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public var date: Date { Date(timeIntervalSince1970: Double(milliseconds) / 1000) }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool { lhs.milliseconds < rhs.milliseconds }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let ms = Timestamp.parse(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 timestamp: \(text)")
        }
        milliseconds = ms
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// `2026-09-27T15:31:52.925Z`
    public var description: String {
        let (days, msOfDay) = milliseconds.floorDivided(by: 86_400_000)
        let (y, m, d) = Timestamp.civil(fromDays: days)
        let seconds = msOfDay / 1000
        return String(format: "%04lld-%02lld-%02lldT%02lld:%02lld:%02lld.%03lldZ",
                      y, m, d, seconds / 3600, seconds / 60 % 60, seconds % 60, msOfDay % 1000)
    }

    /// Parses `YYYY-MM-DD[T ]HH:MM:SS[.fraction][Z|±HH[:MM]]`. A missing offset means UTC.
    public static func parse(_ text: String) -> Int64? {
        let chars = Array(text.utf8)
        var i = 0
        func number(_ digits: Int) -> Int64? {
            guard i + digits <= chars.count else { return nil }
            var value: Int64 = 0
            for _ in 0..<digits {
                let c = chars[i]
                guard c >= 48 && c <= 57 else { return nil }
                value = value * 10 + Int64(c - 48)
                i += 1
            }
            return value
        }
        func expect(_ options: [UInt8]) -> Bool {
            guard i < chars.count, options.contains(chars[i]) else { return false }
            i += 1
            return true
        }
        let colon = UInt8(ascii: ":"), dash = UInt8(ascii: "-")
        guard let year = number(4), expect([dash]), let month = number(2), expect([dash]), let day = number(2),
              expect([UInt8(ascii: "T"), UInt8(ascii: "t"), UInt8(ascii: " ")]),
              let hour = number(2), expect([colon]), let minute = number(2), expect([colon]), let second = number(2),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }

        var fractionMs: Int64 = 0
        if i < chars.count && chars[i] == UInt8(ascii: ".") {
            i += 1
            var digits: [Int64] = []
            while i < chars.count, chars[i] >= 48 && chars[i] <= 57 {
                digits.append(Int64(chars[i] - 48))
                i += 1
            }
            guard !digits.isEmpty else { return nil }
            let padded = digits + [0, 0, 0]
            fractionMs = padded[0] * 100 + padded[1] * 10 + padded[2]
            // Round to the nearest millisecond.
            if digits.count > 3 && digits[3] >= 5 { fractionMs += 1 }
        }

        var offsetMinutes: Int64 = 0
        if i < chars.count {
            let sign = chars[i]
            if sign == UInt8(ascii: "Z") || sign == UInt8(ascii: "z") {
                i += 1
            } else if sign == UInt8(ascii: "+") || sign == dash {
                i += 1
                guard let oh = number(2) else { return nil }
                var om: Int64 = 0
                if i < chars.count {
                    if chars[i] == colon { i += 1 }
                    guard let parsed = number(2) else { return nil }
                    om = parsed
                }
                offsetMinutes = (oh * 60 + om) * (sign == dash ? -1 : 1)
            } else {
                return nil
            }
        }
        guard i == chars.count else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offsetMinutes * 60
        return seconds * 1000 + fractionMs
    }

    // Howard Hinnant's days-from-civil algorithms (proleptic Gregorian calendar, day 0 = 1970-01-01).

    static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(fromDays days: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

private extension Int64 {
    /// Division rounding toward negative infinity, so times before 1970 format correctly.
    func floorDivided(by divisor: Int64) -> (quotient: Int64, remainder: Int64) {
        var q = self / divisor
        var r = self % divisor
        if r < 0 {
            q -= 1
            r += divisor
        }
        return (q, r)
    }
}
