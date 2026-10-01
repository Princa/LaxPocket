import SwiftUI
import LaxPocketCore

/// The wall ball routine: built-in drills and the athlete's own. Tap one to change it, hide it or (for the athlete's own) delete it.
struct WallballDrillsView: View {
    /// Which drill the editor sheet is for; nil for a new one.
    private struct EditTarget: Identifiable {
        let id = UUID()
        var drill: WallballDrill?
    }

    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var editing: EditTarget?

    var body: some View {
        let library = store.data.wallballLibrary
        let shown = library.filter { !$0.isHidden }
        let hidden = library.filter(\.isHidden)
        let totals = WallballStats.byDrill(store.data.wallballSessions)

        List {
            Section {
                ForEach(shown) { drill in row(drill, reps: totals[drill.id]?.total ?? 0) }
                Button { editing = EditTarget() } label: {
                    Label("Add a drill", systemImage: "plus").font(.system(size: 15, weight: .semibold))
                }
            } footer: {
                Text("Every drill here is offered when logging reps and setting up a challenge. Right & left drills count each hand separately.")
            }
            if !hidden.isEmpty {
                Section {
                    ForEach(hidden) { drill in row(drill, reps: totals[drill.id]?.total ?? 0) }
                } header: {
                    Text("Hidden")
                } footer: {
                    Text("Hidden drills keep their history but aren’t offered for new sessions.")
                }
            }
        }
        .navigationTitle("Wall ball drills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = EditTarget() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a drill")
            }
        }
        .sheet(item: $editing) { target in WallballDrillEditorView(drill: target.drill) }
    }

    private func row(_ drill: WallballDrill, reps: Int) -> some View {
        Button { editing = EditTarget(drill: drill) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(drill.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        if !drill.isBuiltIn {
                            Pill(text: "Mine", background: theme.accentTint, foreground: theme.accentText)
                        }
                    }
                    Text(subtitle(drill, reps: reps))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.caption)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the drill to edit")
    }

    private func subtitle(_ drill: WallballDrill, reps: Int) -> String {
        var parts = [drill.hands.title, "\(drill.defaultReps) reps\(drill.hands == .each ? " a hand" : "")"]
        if reps > 0 { parts.append("\(reps.formatted()) logged") }
        return parts.joined(separator: " · ")
    }
}

/// Adds a wall ball drill or changes one.
struct WallballDrillEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let id: String
    private let isNew: Bool
    @State private var name: String
    @State private var detail: String
    @State private var hands: DrillHands
    @State private var defaultReps: Int
    @State private var isHidden: Bool
    @State private var confirmDelete = false
    /// Called with a new drill once it's saved.
    var onAdd: ((WallballDrill) -> Void)?

    init(drill: WallballDrill? = nil, onAdd: ((WallballDrill) -> Void)? = nil) {
        id = drill?.id ?? WallballDrill.newID()
        isNew = drill == nil
        _name = State(initialValue: drill?.name ?? "")
        _detail = State(initialValue: drill?.detail ?? "")
        _hands = State(initialValue: drill?.hands ?? .each)
        _defaultReps = State(initialValue: drill?.defaultReps ?? WallballDrill.standardReps)
        _isHidden = State(initialValue: drill?.isHidden ?? false)
        self.onAdd = onAdd
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var builtIn: WallballDrill? { WallballCatalog.builtIn(id: id) }
    private var repsLogged: Int { WallballStats.byDrill(store.data.wallballSessions)[id]?.total ?? 0 }

    private var drill: WallballDrill {
        WallballDrill(id: id, name: trimmedName, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), hands: hands,
                      defaultReps: defaultReps, isHidden: isHidden)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Twister", text: $name)
                    TextField("How to do it", text: $detail, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Picker("Hands", selection: $hands) {
                        ForEach(DrillHands.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $defaultReps, in: WallballDrill.defaultRepsRange, step: 5) {
                        HStack {
                            Text("Default reps")
                            Spacer()
                            Text(hands == .each ? "\(defaultReps) a hand" : "\(defaultReps)")
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                } footer: {
                    Text(hands == .each
                         ? "Right and left are counted separately, so the dashboard can show the balance between hands."
                         : "For drills that use both hands at once or switch every rep. Counted once.")
                }

                if !isNew {
                    Section {
                        Toggle("Hide from new sessions", isOn: $isHidden)
                        if let builtIn, builtIn != drill {
                            Button("Reset to the original") {
                                store.resetWallballDrill(id)
                                dismiss()
                            }
                        }
                        if builtIn == nil {
                            Button("Delete drill", role: .destructive) { confirmDelete = true }
                                .disabled(repsLogged > 0)
                        }
                    } footer: {
                        if builtIn == nil && repsLogged > 0 {
                            Text("\(repsLogged.formatted()) reps are logged with this drill, so it can be hidden but not deleted.")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add drill" : "Edit drill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete \(trimmedName.isEmpty ? "this drill" : trimmedName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteWallballDrill(id)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        store.saveWallballDrill(drill)
        if isNew { onAdd?(drill) }
        dismiss()
    }
}
