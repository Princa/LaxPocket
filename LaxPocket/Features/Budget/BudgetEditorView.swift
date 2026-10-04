import SwiftUI
import LaxPocketCore

/// Sets one season's budget: the overall amount, and what's set aside for each program running that season.
struct BudgetEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let season: Int
    private let programs: [Program]
    private let previous: [String: Double]
    @State private var overallText: String
    @State private var programTexts: [String: String]

    init(season: Int, data: AppData) {
        self.season = season
        // Programs running this season, plus any with a budget here even though their seasons say otherwise.
        programs = data.programs.filter { $0.runs(in: season) || data.programBudget($0.id, season: season) > 0 }
        previous = Dictionary(data.programBudgets.filter { $0.season == season - 1 }.map { ($0.programID, $0.amount) }, uniquingKeysWith: { a, _ in a })
        let overall = data.budget(for: season)
        _overallText = State(initialValue: overall > 0 ? AmountText.string(overall) : "")
        _programTexts = State(initialValue: Dictionary(uniqueKeysWithValues: programs.map { program in
            let amount = data.programBudget(program.id, season: season)
            return (program.id, amount > 0 ? AmountText.string(amount) : "")
        }))
    }

    private var label: String { AthleteProfile.seasonLabel(start: season) }
    private var overall: Double { AmountText.parse(overallText) ?? 0 }
    private var allocated: Double { programs.reduce(0) { $0 + (AmountText.parse(programTexts[$1.id] ?? "") ?? 0) } }
    private var hasInvalid: Bool {
        ([overallText] + Array(programTexts.values)).contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty && (AmountText.parse($0) ?? -1) < 0 }
    }
    /// Programs with a budget last season and none typed in yet.
    private var canCopyPrevious: Bool {
        programs.contains { previous[$0.id] != nil && (programTexts[$0.id] ?? "").isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Season budget") {
                        TextField("0", text: $overallText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Everything for \(label): program fees plus gear, travel and anything else. Leave it blank to use the program budgets added up.")
                }

                Section {
                    if programs.isEmpty {
                        Text("No programs run in \(label). Add one under Programs, or widen a program’s seasons.")
                            .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    }
                    ForEach(programs) { program in
                        LabeledContent {
                            TextField("0", text: binding(program.id))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.name)
                                if !program.seasonsText.isEmpty {
                                    Text(program.seasonsText).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                                }
                            }
                        }
                    }
                    if canCopyPrevious {
                        Button("Fill in from \(AthleteProfile.seasonLabel(start: season - 1))") {
                            for program in programs where (programTexts[program.id] ?? "").isEmpty {
                                if let amount = previous[program.id] { programTexts[program.id] = AmountText.string(amount) }
                            }
                        }
                    }
                } header: {
                    Text("Programs in \(label)")
                } footer: {
                    Text(programsFooter)
                }
            }
            .navigationTitle("\(label) budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(hasInvalid)
                }
            }
        }
    }

    private var programsFooter: String {
        let base = "A program that runs several seasons has its own budget each season."
        guard allocated > 0 else { return base }
        if overall > 0 {
            let over = allocated > overall + 0.005
            return "Programs add up to \(Formatters.money(allocated)) of \(Formatters.money(overall))\(over ? ", more than the season budget" : ""). \(base)"
        }
        return "Programs add up to \(Formatters.money(allocated)). \(base)"
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { programTexts[id] ?? "" }, set: { programTexts[id] = $0 })
    }

    private func save() {
        store.setBudgets(season: season, overall: overall,
                         programs: programTexts.mapValues { AmountText.parse($0) ?? 0 })
        dismiss()
    }
}
