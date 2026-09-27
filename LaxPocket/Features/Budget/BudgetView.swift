import SwiftUI
import LaxPocketCore

struct BudgetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var showAdd = false
    @State private var showAll = false

    var body: some View {
        let expenses = store.data.expenses.sorted { $0.date > $1.date }
        let summary = BudgetMath.summary(expenses: expenses, budget: store.data.seasonBudget)
        let nextShowcase = Season.upcoming(store.data.events, from: store.now).first { $0.kind == .showcase }
        let recent = showAll ? expenses : Array(expenses.prefix(5))

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        ScreenTitle(text: "Budget")
                        Text("\(store.profile.season) season · all amounts CAD").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(theme.primary, in: Circle())
                    }
                    .accessibilityLabel("Add an expense")
                }

                Card(padding: 20, radius: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spent so far").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Formatters.money(summary.spent)).font(.display(54)).foregroundStyle(theme.primary)
                                Text("of \(Formatters.money(summary.budget))").font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                            }
                        }
                        ProgressView(value: min(summary.fractionUsed, 1))
                            .tint(summary.isOverBudget ? theme.accentText : theme.primary)
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Formatters.money(summary.remaining)).font(.display(24))
                                Text(summary.isOverBudget ? "Over budget" : "Remaining").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int((summary.fractionUsed * 100).rounded()))%").font(.display(24))
                                Text("Of budget used").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let showcase = nextShowcase {
                            Text("Coming up: \(showcase.title) travel & lodging")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.accentText)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.accentTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                if !summary.byCategory.isEmpty {
                    SectionHeader(title: "By category").padding(.top, 8)
                    Card(padding: 0) {
                        ForEach(Array(summary.byCategory.enumerated()), id: \.element.id) { index, row in
                            categoryRow(row, expenses: expenses).padding(.horizontal, 16)
                            if index < summary.byCategory.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 16) }
                        }
                    }
                }

                SectionHeader(title: "Recent") {
                    if expenses.count > 5 {
                        Button(showAll ? "Show less" : "See all") { showAll.toggle() }
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.top, 8)

                if expenses.isEmpty {
                    Card { Text("No expenses yet. Tap + to add fees, coaching, travel or gear.").font(.system(size: 14)).foregroundStyle(AppTheme.ink2) }
                } else {
                    Card(padding: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, expense in
                            expenseRow(expense).padding(.horizontal, 14)
                                .contextMenu {
                                    Button(role: .destructive) { store.deleteExpenses([expense.id]) } label: { Label("Delete", systemImage: "trash") }
                                }
                            if index < recent.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAdd) { AddExpenseView() }
    }

    private func categoryRow(_ row: CategorySpend, expenses: [Expense]) -> some View {
        let names = Array(Set(expenses.filter { $0.category == row.category }.map { $0.title.components(separatedBy: " · ").first ?? $0.title })).sorted()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.category.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(Formatters.money(row.amount)).font(.system(size: 15, weight: .semibold))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.background)
                    Capsule().fill(theme.primary).frame(width: proxy.size.width * row.relativeToLargest)
                }
            }
            .frame(height: 6)
            HStack {
                Text(names.prefix(3).joined(separator: " · ")).lineLimit(1)
                Spacer()
                Text("\(Int((row.share * 100).rounded()))%")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.caption)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(Formatters.monthShort(expense.date)).font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.caption)
                Text(Formatters.dayNumber(expense.date)).font(.display(22))
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(expense.note.isEmpty ? expense.category.title : "\(expense.category.title) · \(expense.note)")
                    .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
            }
            Spacer()
            Text(Formatters.money(expense.amount)).font(.system(size: 15, weight: .semibold))
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

struct AddExpenseView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amountText = ""
    @State private var category: ExpenseCategory = .coaching
    @State private var date = Date()
    @State private var note = ""

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it? e.g. NextLevel · 5-pack", text: $title)
                    TextField("Amount (CAD)", text: $amountText).keyboardType(.decimalPad)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount else { return }
                        store.addExpense(Expense(date: date, title: title.isEmpty ? category.title : title, category: category, amount: amount, note: note))
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(amount == nil)
                }
            }
        }
    }
}
