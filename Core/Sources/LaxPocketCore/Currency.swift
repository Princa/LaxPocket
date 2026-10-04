import Foundation

/// A currency an expense can be paid in. Budgets and totals are always in Canadian dollars; an expense paid in US
/// dollars keeps what was paid and is converted to CAD at an exchange rate.
public enum Currency: String, Codable, CaseIterable, Identifiable, Sendable {
    case cad = "CAD"
    case usd = "USD"

    public var id: String { rawValue }

    /// "$" for Canadian dollars, "US$" for US dollars.
    public var symbol: String {
        switch self {
        case .cad: return "$"
        case .usd: return "US$"
        }
    }

    /// A currency added by a newer version reads as CAD, which is what the expense's `amount` is in anyway.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Currency(rawValue: raw) ?? .cad
    }
}

/// Canadian dollars per US dollar.
public enum ExchangeRate {
    /// The starting rate for a profile until it's set in the app. Not a live rate.
    public static let defaultUSDToCAD = 1.38
    /// Rates the app and the database accept.
    public static let range: ClosedRange<Double> = 0.5...3

    /// A typed rate kept in range and to four decimals, the way it's stored.
    public static func normalized(_ rate: Double) -> Double {
        guard rate.isFinite, rate > 0 else { return defaultUSDToCAD }
        return ((min(max(rate, range.lowerBound), range.upperBound)) * 10_000).rounded() / 10_000
    }

    /// An amount in Canadian dollars, to the cent.
    public static func cad(_ amount: Double, in currency: Currency, rate: Double) -> Double {
        switch currency {
        case .cad: return amount
        case .usd: return (amount * rate * 100).rounded() / 100
        }
    }

    /// A Canadian-dollar amount shown in another currency. US dollars use the rate given (the profile's).
    public static func shown(_ cad: Double, in currency: Currency, rate: Double) -> Double {
        switch currency {
        case .cad: return cad
        case .usd: return rate > 0 ? cad / rate : cad
        }
    }
}

extension Expense {
    /// What was paid, in the currency it was paid in.
    public var paidAmount: Double { currency == .cad ? amount : (originalAmount ?? amount) }

    /// Canadian dollars per unit of the currency it was paid in, for an expense not paid in CAD.
    public var exchangeRate: Double? {
        guard currency != .cad, let original = originalAmount, original > 0 else { return nil }
        return amount / original
    }

    /// Sets what was paid and in which currency, and the amount in CAD at the rate.
    public mutating func setPaid(_ paid: Double, in currency: Currency, rate: Double) {
        self.currency = currency
        originalAmount = currency == .cad ? nil : paid
        amount = ExchangeRate.cad(paid, in: currency, rate: rate)
    }
}

extension AppData {
    /// Expenses paid in US dollars.
    public var usdExpenses: [Expense] {
        expenses.filter { $0.currency == .usd && $0.originalAmount != nil }
    }

    /// Sets the exchange rate. With `reconvert`, expenses paid in US dollars are converted again at the new rate;
    /// otherwise they keep the rate they were recorded at.
    public mutating func setUSDToCAD(_ rate: Double, reconvert: Bool) {
        profile.usdToCAD = ExchangeRate.normalized(rate)
        guard reconvert else { return }
        for index in expenses.indices where expenses[index].currency == .usd {
            guard let paid = expenses[index].originalAmount else { continue }
            expenses[index].amount = ExchangeRate.cad(paid, in: .usd, rate: profile.usdToCAD)
        }
    }
}
