import SwiftUI
import LaxPocketCore

/// One program's money: budget and spending for a season, every season it has figures for, and its expenses.
/// With no program, the expenses that aren't for one.
struct ProgramBudgetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    let programID: String?
    @State var season: Int
    @State private var editing: ExpenseEditTarget?
    @State private var showBudgetEditor = false

    var body: some View {
        let data = store.data
        let program = programID.flatMap(store.program)
        let expenses = matching(data.expenses(in: season)).sorted { $0.date > $1.date }
        let spent = expenses.reduce(0) { $0 + $1.amount }
        let budget = program.map { data.programBudget($0.id, season: season) } ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: program?.name ?? "Other expenses")
                    Text(subtitle(program)).font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                }

                Card(padding: 20, radius: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(AthleteProfile.seasonLabel(start: season)) season").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(store.money(spent)).font(.display(44)).foregroundStyle(theme.primary)
                            Text(budget > 0 ? "of \(store.money(budget))" : (program == nil ? "spent" : "spent · no budget set"))
                                .font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                        }
                        if budget > 0 {
                            ProgressView(value: min(spent / budget, 1))
                                .tint(spent > budget ? theme.accentText : theme.primary)
                                .scaleEffect(x: 1, y: 2, anchor: .center)
                            Text(spent > budget ? "\(store.money(spent - budget)) over budget" : "\(store.money(budget - spent)) left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(spent > budget ? theme.accentText : AppTheme.ink2)
                        }
                    }
                }

                if program != nil {
                    let seasons = seasons(for: data)
                    if seasons.count > 1 {
                        SectionHeader(title: "By season").padding(.top, 8)
                        Card(padding: 0) {
                            ForEach(Array(seasons.enumerated()), id: \.element) { index, s in
                                seasonRow(s, data: data)
                                if index < seasons.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                            }
                        }
                    }
                }

                SectionHeader(title: "Expenses").padding(.top, 8)
                if expenses.isEmpty {
                    Card {
                        Text("Nothing spent in \(AthleteProfile.seasonLabel(start: season)) yet.")
                            .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    }
                } else {
                    Card(padding: 0) {
                        ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                            Button { editing = ExpenseEditTarget(expense: expense, season: season) } label: {
                                ExpenseListRow(expense: expense, showsProgram: false)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            if index < expenses.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }

                Button { editing = ExpenseEditTarget(programID: programID, season: season) } label: {
                    Label("Add expense", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if program != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Budget") { showBudgetEditor = true }
                }
            }
        }
        .sheet(item: $editing) { target in
            ExpenseEditorView(expense: target.expense, programID: target.programID, season: target.season, tripID: target.tripID,
                              category: target.category)
        }
        .sheet(isPresented: $showBudgetEditor) { BudgetEditorView(season: season, data: store.data) }
    }

    /// This program's expenses, or with no program, the ones not for a program that still exists.
    private func matching(_ expenses: [Expense]) -> [Expense] {
        if let programID { return expenses.filter { $0.programID == programID } }
        return expenses.filter { $0.programID.flatMap(store.program) == nil }
    }

    private func subtitle(_ program: Program?) -> String {
        guard let program else { return "Expenses that aren’t for a program" }
        return [program.detail, program.seasonsText].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Seasons this program has a budget or expenses in, plus every season in its range when it has both ends.
    private func seasons(for data: AppData) -> [Int] {
        guard let programID, let program = store.program(programID) else { return [season] }
        var seasons: Set<Int> = [season]
        seasons.formUnion(data.programBudgets.filter { $0.programID == programID }.map(\.season))
        seasons.formUnion(data.expenses.filter { $0.programID == programID }.map(\.season))
        if let first = program.firstSeason, let last = program.lastSeason, last >= first, last - first < 10 {
            seasons.formUnion(first...last)
        }
        return seasons.sorted(by: >)
    }

    private func seasonRow(_ s: Int, data: AppData) -> some View {
        let spent = matching(data.expenses(in: s)).reduce(0) { $0 + $1.amount }
        let budget = programID.map { data.programBudget($0, season: s) } ?? 0
        return Button { season = s } label: {
            HStack {
                Text(AthleteProfile.seasonLabel(start: s)).font(.system(size: 15, weight: s == season ? .bold : .regular))
                if s == season { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.primary) }
                Spacer()
                Text(budget > 0 ? "\(store.money(spent)) of \(store.money(budget))" : store.money(spent))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(budget > 0 && spent > budget ? theme.accentText : AppTheme.ink2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
