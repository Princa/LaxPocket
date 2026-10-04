import SwiftUI
import LaxPocketCore

/// Adds an expense, or edits one: what it was, the amount, the program and season it counts toward, and notes.
struct ExpenseEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The expense being edited; nil for a new one.
    let expense: Expense?
    @State private var title: String
    @State private var amountText: String
    @State private var category: ExpenseCategory
    @State private var date: Date
    @State private var season: Int
    @State private var programID: String?
    @State private var note: String
    @State private var confirmDelete = false

    /// A new expense can start with a program and season filled in.
    init(expense: Expense? = nil, programID: String? = nil, season: Int? = nil) {
        self.expense = expense
        let date = expense?.date ?? Date()
        _title = State(initialValue: expense?.title ?? "")
        _amountText = State(initialValue: expense.map { AmountText.string($0.amount) } ?? "")
        _category = State(initialValue: expense?.category ?? .coaching)
        _date = State(initialValue: date)
        _season = State(initialValue: expense?.season ?? season ?? AthleteProfile.seasonStart(for: date))
        _programID = State(initialValue: expense?.programID ?? programID)
        _note = State(initialValue: expense?.note ?? "")
    }

    private var isNew: Bool { expense == nil }
    private var amount: Double? { AmountText.parse(amountText).flatMap { $0 >= 0 ? $0 : nil } }
    private var program: Program? { programID.flatMap(store.program) }

    /// Programs that run in the chosen season, plus the one already picked.
    private var programChoices: [Program] {
        store.data.programs.filter { $0.runs(in: season) || $0.id == programID }
    }

    private var seasonChoices: [Int] {
        let current = store.profile.currentSeason(now: store.now)
        let seasons = Set(store.data.budgetSeasons(current: current)).union([season, AthleteProfile.seasonStart(for: date), current - 1])
        return seasons.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it? e.g. Spring season fee", text: $title)
                    TextField("Amount (CAD)", text: $amountText).keyboardType(.decimalPad)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section {
                    Picker("Season", selection: $season) {
                        ForEach(seasonChoices, id: \.self) { Text(AthleteProfile.seasonLabel(start: $0)).tag($0) }
                    }
                    Picker("Program", selection: $programID) {
                        Text("None").tag(String?.none)
                        ForEach(programChoices) { program in
                            Text(program.name).tag(String?.some(program.id))
                        }
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    Text(budgetFooter)
                }

                Section("Notes") {
                    TextField("Receipt, who paid, what’s still owing…", text: $note, axis: .vertical)
                        .lineLimit(3...10)
                }

                if !isNew {
                    Section {
                        Button("Delete expense", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(amount == nil)
                }
            }
            .onAppear {
                if isNew, let program { category = .suggested(for: program.group) }
            }
            .onChange(of: date) { old, new in
                // The season follows the date until it's picked by hand.
                if season == AthleteProfile.seasonStart(for: old) { season = AthleteProfile.seasonStart(for: new) }
            }
            .onChange(of: programID) { _, _ in
                if isNew, let program { category = .suggested(for: program.group) }
            }
            .confirmationDialog("Delete this expense?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let expense { store.deleteExpenses([expense.id]) }
                    dismiss()
                }
            }
        }
    }

    private var budgetFooter: String {
        let label = AthleteProfile.seasonLabel(start: season)
        if let program { return "Counts toward \(program.name)’s \(label) budget and the \(label) season total." }
        return "Counts toward the \(label) season total. Pick a program to track it against that program’s budget too."
    }

    private func save() {
        guard let amount else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.saveExpense(Expense(id: expense?.id ?? UUID(), date: date, title: trimmed.isEmpty ? (program?.name ?? category.title) : trimmed,
                                  category: category, amount: amount, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                  programID: program?.id, season: season))
        dismiss()
    }
}
