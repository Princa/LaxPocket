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
    @State private var confirmDelete = false

    /// Pass an existing program to edit it, or a group to start a new one in.
    init(program: Program? = nil, group: ProgramGroup = .teams) {
        id = program?.id ?? Program.newID()
        _name = State(initialValue: program?.name ?? "")
        _detail = State(initialValue: program?.detail ?? "")
        _group = State(initialValue: program?.group ?? group)
        _category = State(initialValue: program == nil ? Program.defaultCategory(for: group) : program?.sessionCategory)
        _monogram = State(initialValue: program?.monogram ?? "")
    }

    private var isNew: Bool { store.program(id) == nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sessionCount: Int { store.data.sessionCountByProgram[id] ?? 0 }

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
                        Text("Not logged").tag(SessionCategory?.none)
                    }
                } footer: {
                    Text("Programs with a session type show up in Log session and count toward that part of the weekly hours.")
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
                        Button("Delete program", role: .destructive) { confirmDelete = true }
                            .disabled(sessionCount > 0)
                    } footer: {
                        if sessionCount > 0 {
                            Text(sessionCount == 1 ? "1 session is logged with this program. Delete it first." : "\(sessionCount) sessions are logged with this program. Delete them first.")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add program" : "Edit program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: group) { _, newGroup in category = Program.defaultCategory(for: newGroup) }
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
                                  sessionCategory: category, monogram: badge.isEmpty ? Program.suggestedMonogram(for: trimmedName) : String(badge.prefix(3))))
        dismiss()
    }
}
