import SwiftUI
import LaxPocketCore

/// The practice drills: built-ins and the athlete's own, by kind. Tap one to change it, hide it or (for the athlete's
/// own) delete it.
struct PracticeDrillsView: View {
    /// Which drill the editor sheet is for; nil for a new one.
    private struct EditTarget: Identifiable {
        let id = UUID()
        var drill: PracticeDrill?
    }

    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var editing: EditTarget?

    var body: some View {
        let library = store.data.practiceLibrary
        let hidden = library.filter(\.isHidden)
        let totals = PracticeStats.byDrill(store.data.practiceSessions, library: library)

        List {
            ForEach(PracticeKind.allCases) { kind in
                let shown = library.filter { $0.kind == kind && !$0.isHidden }
                if !shown.isEmpty {
                    Section(kind.title) {
                        ForEach(shown) { drill in row(drill, totals: totals[drill.id]) }
                    }
                }
            }
            Section {
                Button { editing = EditTarget() } label: {
                    Label("Add a drill", systemImage: "plus").font(.system(size: 15, weight: .semibold))
                }
            } footer: {
                Text("Every drill here is offered when logging practice and setting up a challenge.")
            }
            if !hidden.isEmpty {
                Section {
                    ForEach(hidden) { drill in row(drill, totals: totals[drill.id]) }
                } header: {
                    Text("Hidden")
                } footer: {
                    Text("Hidden drills keep their history but aren’t offered for new sessions.")
                }
            }
        }
        .navigationTitle("Practice drills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = EditTarget() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a drill")
            }
        }
        .sheet(item: $editing) { target in PracticeDrillEditorView(drill: target.drill) }
    }

    private func row(_ drill: PracticeDrill, totals: PracticeTotals?) -> some View {
        Button { editing = EditTarget(drill: drill) } label: {
            HStack(spacing: 12) {
                Circle().fill(theme.color(for: drill.kind)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(drill.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        if !drill.isBuiltIn {
                            Pill(text: "Mine", background: theme.accentTint, foreground: theme.accentText)
                        }
                    }
                    Text(subtitle(drill, totals: totals))
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

    private func subtitle(_ drill: PracticeDrill, totals: PracticeTotals?) -> String {
        var parts = ["\(drill.measure.format(drill.defaultAmount)) to start"]
        if drill.tracksTarget { parts.append("on target counted") }
        if let totals, !totals.isEmpty, let logged = PracticeSummary.line(totals) { parts.append("\(logged) logged") }
        return parts.joined(separator: " · ")
    }
}

/// Adds a practice drill or changes one.
struct PracticeDrillEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let id: String
    private let isNew: Bool
    @State private var name: String
    @State private var detail: String
    @State private var kind: PracticeKind
    @State private var measure: PracticeMeasure
    @State private var tracksTarget: Bool
    @State private var defaultAmount: Int
    @State private var isHidden: Bool
    @State private var confirmDelete = false
    /// Called with a new drill once it's saved.
    var onAdd: ((PracticeDrill) -> Void)?

    init(drill: PracticeDrill? = nil, onAdd: ((PracticeDrill) -> Void)? = nil) {
        id = drill?.id ?? PracticeDrill.newID()
        isNew = drill == nil
        _name = State(initialValue: drill?.name ?? "")
        _detail = State(initialValue: drill?.detail ?? "")
        _kind = State(initialValue: drill?.kind ?? .shooting)
        _measure = State(initialValue: drill?.measure ?? .shots)
        _tracksTarget = State(initialValue: drill?.tracksTarget ?? true)
        _defaultAmount = State(initialValue: drill?.defaultAmount ?? 25)
        _isHidden = State(initialValue: drill?.isHidden ?? false)
        self.onAdd = onAdd
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var builtIn: PracticeDrill? { PracticeCatalog.builtIn(id: id) }
    /// Once something is logged with a drill, what it counts can't change, or the history would read differently.
    private var isUsed: Bool { store.isPracticeDrillUsed(id) }

    private var drill: PracticeDrill {
        PracticeDrill(id: id, name: trimmedName, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
                      measure: measure, tracksTarget: tracksTarget, defaultAmount: defaultAmount, isHidden: isHidden)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Tarp corners", text: $name)
                    TextField("How to do it", text: $detail, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(PracticeKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Counts", selection: $measure) {
                        ForEach(PracticeMeasure.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isUsed)
                    if measure == .shots {
                        Toggle("Count shots on target", isOn: $tracksTarget)
                    }
                    Stepper(value: $defaultAmount, in: PracticeDrill.defaultAmountRange, step: measure.step) {
                        HStack {
                            Text("To start")
                            Spacer()
                            Text(measure.format(defaultAmount)).foregroundStyle(AppTheme.muted)
                        }
                    }
                } footer: {
                    Text(isUsed
                         ? "Practice is logged with this drill, so what it counts stays as it is."
                         : "Shots add up toward the weekly shot goal; stickhandling minutes toward the stickhandling goal.")
                }

                if !isNew {
                    Section {
                        Toggle("Hide from new sessions", isOn: $isHidden)
                        if let builtIn, builtIn != drill {
                            Button("Reset to the original") {
                                store.resetPracticeDrill(id)
                                dismiss()
                            }
                        }
                        if builtIn == nil {
                            Button("Delete drill", role: .destructive) { confirmDelete = true }
                                .disabled(isUsed)
                        }
                    } footer: {
                        if builtIn == nil && isUsed {
                            Text("Practice is logged with this drill, so it can be hidden but not deleted.")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add drill" : "Edit drill")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: kind) { _, newKind in
                // A new drill starts counting what its kind usually counts.
                guard isNew else { return }
                measure = newKind == .shooting ? .shots : newKind == .stickhandling ? .minutes : .reps
                defaultAmount = newKind == .stickhandling ? 3 : 25
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete \(trimmedName.isEmpty ? "this drill" : trimmedName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deletePracticeDrill(id)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        store.savePracticeDrill(drill)
        if isNew { onAdd?(drill) }
        dismiss()
    }
}
