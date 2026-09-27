import Foundation

public enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case teamFees
    case coaching
    case fitness
    case travel
    case showcases
    case equipment
    case facility

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .teamFees: return "Team & league fees"
        case .coaching: return "Private coaching"
        case .fitness: return "Strength & fitness"
        case .travel: return "Travel & lodging"
        case .showcases: return "Showcases & camps"
        case .equipment: return "Equipment"
        case .facility: return "Facility membership"
        }
    }
}

public struct Expense: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var title: String
    public var category: ExpenseCategory
    /// Amount in the season's currency (CAD by default).
    public var amount: Double
    public var note: String

    public init(id: UUID = UUID(), date: Date, title: String, category: ExpenseCategory, amount: Double, note: String = "") {
        self.id = id
        self.date = date
        self.title = title
        self.category = category
        self.amount = amount
        self.note = note
    }
}

public struct CategorySpend: Identifiable, Equatable, Sendable {
    public var category: ExpenseCategory
    public var amount: Double
    /// Share of total spend, 0...1.
    public var share: Double
    /// Amount relative to the largest category, 0...1 — used for bar lengths.
    public var relativeToLargest: Double

    public var id: ExpenseCategory { category }
}

public struct BudgetSummary: Equatable, Sendable {
    public var budget: Double
    public var spent: Double
    public var byCategory: [CategorySpend]

    public var remaining: Double { budget - spent }
    public var fractionUsed: Double { budget > 0 ? spent / budget : 0 }
    public var isOverBudget: Bool { spent > budget && budget > 0 }
}

public enum BudgetMath {
    public static func summary(expenses: [Expense], budget: Double) -> BudgetSummary {
        let spent: Double = expenses.reduce(0.0) { $0 + $1.amount }
        var totals: [ExpenseCategory: Double] = [:]
        for expense in expenses { totals[expense.category, default: 0] += expense.amount }
        let largest: Double = totals.values.max() ?? 0

        var rows: [CategorySpend] = []
        for (category, amount) in totals {
            let share: Double = spent > 0 ? amount / spent : 0
            let relative: Double = largest > 0 ? amount / largest : 0
            rows.append(CategorySpend(category: category, amount: amount, share: share, relativeToLargest: relative))
        }
        // Largest spend first; ties in title order so the list is stable.
        rows.sort { (a: CategorySpend, b: CategorySpend) -> Bool in
            if a.amount != b.amount { return a.amount > b.amount }
            return a.category.title < b.category.title
        }
        return BudgetSummary(budget: budget, spent: spent, byCategory: rows)
    }
}
