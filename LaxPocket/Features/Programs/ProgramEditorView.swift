import SwiftUI
import LaxPocketCore

/// Adds or edits a team, coach, facility or event the athlete trains with.
struct ProgramEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let id: String
    @State private var name: String
    @State private var detail: String
    @State private var group: ProgramGroup
    @State private var category: SessionCategory?
    @State private var monogram: String
    @State private var firstSeason: Int?
    @State private var lastSeason: Int?
    @State private var confirmDelete = false

    /// Pass an existing program to edit it, or a group to start a new one in.
    init(program: Program? = nil, group: ProgramGroup = .teams) {
        id = program?.id ?? Program.newID()
        _name = State(initialValue: program?.name ?? "")
        _detail = State(initialValue: program?.detail ?? "")
        _group = State(initialValue: program?.group ?? group)
        _category = State(initialValue: program == nil ? Program.defaultCategory(for: group) : program?.loggedCategory)
        _monogram = State(initialValue: program?.monogram ?? "")
        _firstSeason = State(initialValue: program?.firstSeason)
        _lastSeason = State(initialValue: program?.lastSeason)
    }

    private var isNew: Bool { store.program(id) == nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sessionCount: Int { store.data.sessionCountByProgram[id] ?? 0 }
    private var expenseCount: Int { store.data.expenses.filter { $0.programID == id }.count }

    /// A few seasons either side of this one, plus whatever is already set.
    private var seasonChoices: [Int] {
        let current = store.profile.currentSeason(now: store.now)
        return Set(Array((current - 4)...(current + 6)) + [firstSeason, lastSeason].compactMap { $0 }).sorted()
    }

    private var title: String {
        let noun = group == .teams ? "team" : "program"
        return isNew ? "Add \(noun)" : "Edit \(noun)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Club 2031", text: $name)
                    TextField("Detail, e.g. Club team · Tue & Thu", text: $detail)
                    Picker("Group", selection: $group) {
                        ForEach(ProgramGroup.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Picker("Sessions count as", selection: $category) {
                        ForEach(SessionCategory.allCases) { Text($0.title).tag(SessionCategory?.some($0)) }
                        // Mental performance programs always log sessions (see Program.loggedCategory).
                        if group != .mental {
                            Text("Not logged").tag(SessionCategory?.none)
                        }
                    }
                } footer: {
                    Text("Programs with a session type show up in Log session and count toward that part of the weekly hours.")
                }

                Section {
                    Picker("First season", selection: $firstSeason) {
                        Text("Not set").tag(Int?.none)
                        ForEach(seasonChoices, id: \.self) { Text(AthleteProfile.seasonLabel(start: $0)).tag(Int?.some($0)) }
                    }
                    Picker("Last season", selection: $lastSeason) {
                        Text("Ongoing").tag(Int?.none)
                        ForEach(seasonChoices.filter { $0 >= (firstSeason ?? .min) }, id: \.self) {
                            Text(AthleteProfile.seasonLabel(start: $0)).tag(Int?.some($0))
                        }
                    }
                } header: {
                    Text("Seasons")
                } footer: {
                    Text("For a team or program that runs over several seasons, e.g. a club team from 2026/27 to 2028/29. Each season gets its own budget on the Budget screen.")
                }

                Section {
                    HStack {
                        Text("Badge")
                        Spacer()
                        TextField(Program.suggestedMonogram(for: name), text: $monogram)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 100)
                    }
                } footer: {
                    Text("Up to 3 letters. Leave blank to use the suggestion.")
                }

                if !isNew {
                    Section {
                        Button(group == .teams ? "Delete team" : "Delete program", role: .destructive) { confirmDelete = true }
                            .disabled(sessionCount > 0 || expenseCount > 0)
                    } footer: {
                        if sessionCount > 0 {
                            Text(sessionCount == 1 ? "1 session is logged with this program. Delete it first." : "\(sessionCount) sessions are logged with this program. Delete them first.")
                        } else if expenseCount > 0 {
                            Text(expenseCount == 1 ? "1 expense is for this program. Delete it or move it to another program first."
                                                   : "\(expenseCount) expenses are for this program. Delete them or move them to another program first.")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: group) { _, newGroup in category = Program.defaultCategory(for: newGroup) }
            .onChange(of: firstSeason) { _, first in
                if let first, let last = lastSeason, last < first { lastSeason = first }
            }
            .confirmationDialog("Delete \(trimmedName.isEmpty ? "this program" : trimmedName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteProgram(id)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let badge = monogram.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        store.saveProgram(Program(id: id, name: trimmedName, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), group: group,
                                  sessionCategory: category, monogram: badge.isEmpty ? Program.suggestedMonogram(for: trimmedName) : String(badge.prefix(3)),
                                  firstSeason: firstSeason, lastSeason: lastSeason))
        dismiss()
    }
}
