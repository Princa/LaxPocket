import SwiftUI
import LaxPocketCore

/// An expense to add or edit in the editor sheet. New ones can start with a program and season filled in.
struct ExpenseEditTarget: Identifiable {
    let id = UUID()
    var expense: Expense?
    var programID: String?
    var season: Int
}

/// Money typed into a text field: "1,850", "$320.50" or "320.5".
enum AmountText {
    static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// "1850" or "320.50", for filling in a field.
    static func string(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}

/// One expense in a list: date, title, category and program, amount, and the start of its notes.
struct ExpenseListRow: View {
    @Environment(AppStore.self) private var store
    let expense: Expense
    /// Leave the program out on a screen that's already about one program.
    var showsProgram = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(Formatters.monthShort(expense.date)).font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.caption)
                Text(Formatters.dayNumber(expense.date)).font(.display(22))
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink).lineLimit(1)
                Text(caption).font(.system(size: 13)).foregroundStyle(AppTheme.caption).lineLimit(1)
                if !expense.note.isEmpty {
                    Label(expense.note, systemImage: "note.text")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ink2)
                        .lineLimit(2)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer()
            Text(Formatters.money(expense.amount)).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron).padding(.top, 2)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the expense to edit")
    }

    private var caption: String {
        guard showsProgram, let id = expense.programID, let program = store.program(id) else { return expense.category.title }
        return "\(expense.category.title) · \(program.name)"
    }
}

extension ExpenseCategory {
    /// What an expense for a program in this group usually is.
    static func suggested(for group: ProgramGroup) -> ExpenseCategory {
        switch group {
        case .teams: return .teamFees
        case .skills, .mental: return .coaching
        case .fitness: return .fitness
        case .showcases, .combine: return .showcases
        }
    }
}
