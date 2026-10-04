import Foundation

public enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case teamFees
    case tournamentFees
    case coaching
    case fitness
    case travel
    case lodging
    case food
    case showcases
    case equipment
    case facility
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .teamFees: return "Team & league fees"
        case .tournamentFees: return "Tournament fees"
        case .coaching: return "Private coaching"
        case .fitness: return "Strength & fitness"
        case .travel: return "Travel"
        case .lodging: return "Hotel & lodging"
        case .food: return "Food & meals"
        case .showcases: return "Showcases & camps"
        case .equipment: return "Equipment"
        case .facility: return "Facility membership"
        case .other: return "Other"
        }
    }

    /// What a tournament trip usually costs, in the order the trip screen lists them.
    public static let tripCategories: [ExpenseCategory] = [.tournamentFees, .travel, .lodging, .food, .other]

    /// A category added by a newer version reads as `other` rather than failing to load.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseCategory(rawValue: raw) ?? .other
    }
}

public struct Expense: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var title: String
    public var category: ExpenseCategory
    /// Amount in Canadian dollars; what counts toward budgets and totals. For an expense paid in another currency, the
    /// amount paid converted at the exchange rate.
    public var amount: Double
    /// What it was paid in.
    public var currency: Currency
    /// What was paid, in `currency`, when that isn't CAD.
    public var originalAmount: Double?
    public var note: String
    /// The program it was for, if any.
    public var programID: String?
    /// The season it counts toward, as the year it starts. Usually the season of `date`, but a fee paid in July can
    /// belong to the season starting in August.
    public var season: Int
    /// The tournament trip it was for, if any.
    public var tripID: UUID?

    public init(id: UUID = UUID(), date: Date, title: String, category: ExpenseCategory, amount: Double, note: String = "",
                programID: String? = nil, season: Int? = nil, tripID: UUID? = nil, currency: Currency = .cad, originalAmount: Double? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.category = category
        self.amount = amount
        self.currency = originalAmount == nil ? .cad : currency
        self.originalAmount = currency == .cad ? nil : originalAmount
        self.note = note
        self.programID = programID
        self.season = season ?? AthleteProfile.seasonStart(for: date)
        self.tripID = tripID
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, title, category, amount, note, programID, season, tripID, currency, originalAmount
    }

    /// Expenses saved before seasons and programs have neither; they count toward the season of their date. Those saved
    /// before trips have no `tripID`, and those saved before currencies were paid in CAD.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(ExpenseCategory.self, forKey: .category)
        amount = try c.decode(Double.self, forKey: .amount)
        originalAmount = try c.decodeIfPresent(Double.self, forKey: .originalAmount)
        let currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? .cad
        self.currency = originalAmount == nil ? .cad : currency
        if self.currency == .cad { originalAmount = nil }
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        programID = try c.decodeIfPresent(String.self, forKey: .programID)
        season = try c.decodeIfPresent(Int.self, forKey: .season) ?? AthleteProfile.seasonStart(for: date)
        tripID = try c.decodeIfPresent(UUID.self, forKey: .tripID)
    }
}

/// The overall budget for one season (given as the year it starts).
public struct SeasonBudget: Codable, Hashable, Sendable {
    public var season: Int
    public var amount: Double
    public var note: String

    public init(season: Int, amount: Double, note: String = "") {
        self.season = season
        self.amount = amount
        self.note = note
    }
}

/// What's set aside for one program in one season. A program that runs several seasons has one per season.
public struct ProgramBudget: Codable, Hashable, Sendable {
    public var programID: String
    public var season: Int
    public var amount: Double
    public var note: String

    public init(programID: String, season: Int, amount: Double, note: String = "") {
        self.programID = programID
        self.season = season
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

/// Spending against one program's budget in a season, or against nothing for expenses with no program.
public struct ProgramSpend: Identifiable, Equatable, Sendable {
    /// Nil for expenses that aren't for a program.
    public var program: Program?
    public var budget: Double
    public var spent: Double
    public var expenseCount: Int

    public var id: String { program?.id ?? "" }
    public var remaining: Double { budget - spent }
    public var fractionUsed: Double { budget > 0 ? spent / budget : 0 }
    public var isOverBudget: Bool { spent > budget && budget > 0 }
}

/// One season's budget: the overall budget, what's set aside per program, and where the money went.
public struct SeasonBudgetSummary: Equatable, Sendable {
    public var season: Int
    /// The overall budget as set; 0 if none.
    public var overall: Double
    /// The program budgets added up.
    public var allocated: Double
    /// Spend against the overall budget, or against the program budgets added up when no overall budget is set.
    public var summary: BudgetSummary
    /// Programs with a budget or spending this season, in program order, then spending with no program.
    public var programs: [ProgramSpend]

    /// Program budgets add up to more than the overall budget.
    public var isOverAllocated: Bool { overall > 0 && allocated > overall + 0.005 }
}

extension AppData {
    /// The overall budget set for a season; 0 if none.
    public func budget(for season: Int) -> Double {
        seasonBudgets.first { $0.season == season }?.amount ?? 0
    }

    /// Sets a season's overall budget; 0 removes it.
    public mutating func setBudget(_ amount: Double, for season: Int) {
        seasonBudgets.removeAll { $0.season == season }
        if amount > 0 { seasonBudgets.append(SeasonBudget(season: season, amount: amount)) }
        seasonBudgets.sort { $0.season < $1.season }
    }

    /// The overall budget for the season the profile is set to.
    public var seasonBudget: Double {
        get { budget(for: profile.currentSeason()) }
        set { setBudget(newValue, for: profile.currentSeason()) }
    }

    /// What's set aside for a program in a season; 0 if nothing.
    public func programBudget(_ programID: String, season: Int) -> Double {
        programBudgets.first { $0.programID == programID && $0.season == season }?.amount ?? 0
    }

    /// Sets a program's budget for a season; 0 removes it.
    public mutating func setProgramBudget(_ amount: Double, programID: String, season: Int) {
        programBudgets.removeAll { $0.programID == programID && $0.season == season }
        if amount > 0 { programBudgets.append(ProgramBudget(programID: programID, season: season, amount: amount)) }
        programBudgets.sort { ($0.season, $0.programID) < ($1.season, $1.programID) }
    }

    public func expenses(in season: Int) -> [Expense] {
        expenses.filter { $0.season == season }
    }

    /// Programs that run in a season.
    public func programs(in season: Int) -> [Program] {
        programs.filter { $0.runs(in: season) }
    }

    /// Seasons worth offering on the Budget screen, newest first: the current and next season, and any season with
    /// expenses, a budget, or a program that starts or ends in it.
    public func budgetSeasons(current: Int) -> [Int] {
        var seasons: Set<Int> = [current, current + 1]
        seasons.formUnion(expenses.map(\.season))
        seasons.formUnion(seasonBudgets.map(\.season))
        seasons.formUnion(programBudgets.map(\.season))
        seasons.formUnion(trips.map(\.season))
        for program in programs {
            if let first = program.firstSeason { seasons.insert(first) }
            if let last = program.lastSeason { seasons.insert(last) }
        }
        return seasons.filter { (2000...2100).contains($0) }.sorted(by: >)
    }
}

public enum BudgetMath {
    /// A season's budget and spending, overall and per program.
    public static func season(_ season: Int, in data: AppData) -> SeasonBudgetSummary {
        let expenses = data.expenses(in: season)
        let overall = data.budget(for: season)
        let budgets = data.programBudgets.filter { $0.season == season }
        let allocated = budgets.reduce(0) { $0 + $1.amount }

        var spentByProgram: [String: (spent: Double, count: Int)] = [:]
        var unassigned: (spent: Double, count: Int) = (0, 0)
        let known = Set(data.programs.map(\.id))
        for expense in expenses {
            if let id = expense.programID, known.contains(id) {
                spentByProgram[id, default: (0, 0)].spent += expense.amount
                spentByProgram[id, default: (0, 0)].count += 1
            } else {
                unassigned.spent += expense.amount
                unassigned.count += 1
            }
        }
        var lines: [ProgramSpend] = []
        for program in data.programs {
            let budget = data.programBudget(program.id, season: season)
            let spend = spentByProgram[program.id] ?? (0, 0)
            guard budget > 0 || spend.count > 0 else { continue }
            lines.append(ProgramSpend(program: program, budget: budget, spent: spend.spent, expenseCount: spend.count))
        }
        if unassigned.count > 0 {
            lines.append(ProgramSpend(program: nil, budget: 0, spent: unassigned.spent, expenseCount: unassigned.count))
        }
        return SeasonBudgetSummary(season: season, overall: overall, allocated: allocated,
                                   summary: summary(expenses: expenses, budget: overall > 0 ? overall : allocated), programs: lines)
    }

    public static func summary(expenses: [Expense], budget: Double) -> BudgetSummary {
        var spent: Double = 0
        var totals: [ExpenseCategory: Double] = [:]
        for expense in expenses {
            spent += expense.amount
            totals[expense.category, default: 0] += expense.amount
        }
        let largest: Double = totals.values.max() ?? 0

        var rows: [CategorySpend] = []
        for (category, amount) in totals {
            let share: Double = spent > 0 ? amount / spent : 0
            let relative: Double = largest > 0 ? amount / largest : 0
            rows.append(CategorySpend(category: category, amount: amount, share: share, relativeToLargest: relative))
        }
        rows.sort(by: Self.isOrderedBefore)
        return BudgetSummary(budget: budget, spent: spent, byCategory: rows)
    }

    /// Largest spend first; ties fall back to the category name.
    private static func isOrderedBefore(_ a: CategorySpend, _ b: CategorySpend) -> Bool {
        if a.amount != b.amount { return a.amount > b.amount }
        return a.category.title < b.category.title
    }
}
