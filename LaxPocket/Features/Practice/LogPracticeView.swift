import SwiftUI
import LaxPocketCore

/// Logs a day's hockey practice, or edits a session. Drills are grouped by kind; each kind can pick all its drills with
/// one amount, and shooting drills can also count how many shots were on target.
struct LogPracticeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The session being edited; nil for a new one.
    private let session: PracticeSession?
    @State private var draft: PracticeDraft
    @State private var date: Date
    @State private var minutes: Int
    @State private var notes: String
    @State private var showAddDrill = false
    @State private var confirmDelete = false

    init(session: PracticeSession? = nil) {
        self.session = session
        _draft = State(initialValue: PracticeDraft(sets: session?.sets ?? []))
        _date = State(initialValue: session?.date ?? Date())
        _minutes = State(initialValue: session?.minutes ?? 0)
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var isNew: Bool { session == nil }

    /// Drills offered: everything not hidden, plus hidden ones already in this session.
    private var drills: [PracticeDrill] {
        store.data.practiceLibrary.filter { !$0.isHidden || draft.isPicked($0.id) }
    }

    /// The latest other session that wasn't a challenge, to repeat.
    private var lastSession: PracticeSession? {
        store.data.practiceSessions.filter { $0.id != session?.id && !$0.isChallenge }.max { $0.date < $1.date }
    }

    var body: some View {
        let library = drills
        let totals = draft.totals(in: library)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isNew, let last = lastSession {
                        Button {
                            draft = PracticeDraft(sets: last.sets)
                        } label: {
                            Label("Same as \(last.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
                                  systemImage: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        }
                        .foregroundStyle(theme.primary)
                    }

                    ForEach(PracticeKind.allCases) { kind in
                        let inKind = library.filter { $0.kind == kind }
                        if !inKind.isEmpty { kindSection(kind, drills: inKind) }
                    }

                    Button { showAddDrill = true } label: {
                        Label("Add a drill", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }

                    detailsCard

                    if !isNew {
                        Button("Delete this session", role: .destructive) { confirmDelete = true }
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) { saveBar(totals) }
            .navigationTitle(isNew ? "Log practice" : session?.isChallenge == true ? "Edit challenge" : "Edit practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(totals.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $showAddDrill) {
                PracticeDrillEditorView { drill in draft.pick(drill) }
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let session { store.deletePracticeSessions([session.id]) }
                    dismiss()
                }
            }
        }
    }

    // MARK: - Pieces

    /// Quick amounts for a kind's drills: picks them all with that amount, or sets every picked one to it.
    private static func quickAmounts(_ kind: PracticeKind) -> [Int] {
        switch kind {
        case .shooting: return [10, 25, 50, 100]
        case .stickhandling: return [2, 3, 5, 10]
        case .passing, .other: return [10, 20, 30, 50]
        }
    }

    private func kindSection(_ kind: PracticeKind, drills: [PracticeDrill]) -> some View {
        let picked = drills.filter { draft.isPicked($0.id) }
        let unit = drills.first?.measure ?? .reps
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: kind.title, color: theme.color(for: kind))
                Spacer()
                Text("\(picked.count) of \(drills.count)").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
            }
            HStack(spacing: 6) {
                ForEach(Self.quickAmounts(kind), id: \.self) { amount in
                    Button(unit == .minutes ? "\(amount) min" : "\(amount)") {
                        if picked.isEmpty { draft.pickAll(drills.filter { !$0.isHidden }, amount: amount) } else { draft.setAll(amount, in: drills) }
                    }
                    .buttonStyle(QuickButtonStyle(color: theme.color(for: kind), filled: false, textColor: AppTheme.ink, expands: true))
                    .accessibilityLabel(picked.isEmpty ? "Pick every \(kind.title.lowercased()) drill with \(unit.format(amount))"
                                        : "Set every picked \(kind.title.lowercased()) drill to \(unit.format(amount))")
                }
            }
            Card(padding: 0, radius: 14) {
                ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                    PracticeDrillRow(drill: drill, draft: $draft)
                        .padding(.horizontal, 14)
                    if index < drills.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 52) }
                }
            }
        }
    }

    private var detailsCard: some View {
        Card(padding: 0, radius: 14) {
            DatePicker("Date", selection: $date, in: ...Date().addingTimeInterval(86_400), displayedComponents: .date)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Divider().overlay(AppTheme.line).padding(.leading, 14)
            HStack {
                Text("Time")
                Spacer()
                RepStepper(value: $minutes, color: theme.primary)
                    .accessibilityLabel("Minutes, if noted")
                Text("min").font(.system(size: 14)).foregroundStyle(AppTheme.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider().overlay(AppTheme.line).padding(.leading, 14)
            TextField("Notes: what felt good, what to work on", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .padding(14)
        }
    }

    private func saveBar(_ totals: PracticeTotals) -> some View {
        let byKind = PracticeStats.byKind([PracticeSession(date: date, sets: draft.sets(in: drills))], library: drills)
        return VStack(spacing: 8) {
            Text(PracticeSummary.line(totals, byKind: byKind) ?? "Pick drills to log practice")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button(isNew ? "Save practice" : "Save changes", action: save)
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                .disabled(totals.isEmpty)
                .opacity(totals.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func save() {
        let sets = draft.sets(in: drills)
        guard !sets.isEmpty else { return }
        var entry = session ?? PracticeSession(date: date, sets: [])
        entry.date = date
        entry.sets = sets
        entry.minutes = (1...1440).contains(minutes) ? minutes : nil
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.savePracticeSession(entry)
        dismiss()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// One drill in the log: tap to pick it, then set the shots, minutes or reps, and for shots, how many were on target.
private struct PracticeDrillRow: View {
    @Environment(\.appTheme) private var theme
    let drill: PracticeDrill
    @Binding var draft: PracticeDraft

    var body: some View {
        let picked = draft.isPicked(drill.id)
        let color = theme.color(for: drill.kind)
        VStack(alignment: .leading, spacing: 10) {
            Button { draft.toggle(drill) } label: {
                HStack(spacing: 12) {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(picked ? color : AppTheme.border)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drill.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        if !picked {
                            Text(drill.detail).font(.system(size: 13)).foregroundStyle(AppTheme.caption).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if picked {
                        RepStepper(value: amount, color: color, step: drill.measure.step)
                            .accessibilityLabel("\(drill.measure.title) for \(drill.name)")
                        Text(drill.measure == .minutes ? "min" : drill.measure.title.lowercased())
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.caption)
                            .frame(width: 34, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(drill.name)
            .accessibilityAddTraits(picked ? .isSelected : [])
            .accessibilityHint(picked ? "Removes the drill" : "Adds the drill")

            if picked && drill.tracksTarget {
                HStack(spacing: 8) {
                    if let target = draft.onTarget(drill.id) {
                        Text("On target").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.ink2)
                        Spacer(minLength: 0)
                        RepStepper(value: onTarget, color: color)
                            .accessibilityLabel("Shots on target for \(drill.name)")
                        Text(percent(target)).font(.system(size: 12)).foregroundStyle(AppTheme.caption).frame(width: 34, alignment: .leading)
                        Button { draft.setOnTarget(nil, drillID: drill.id) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.chevron).frame(width: 32, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop counting on target")
                    } else {
                        Button { draft.setOnTarget(draft.amount(drill.id), drillID: drill.id) } label: {
                            Label("Count on target", systemImage: "scope").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(color)
                        Spacer()
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 12)
    }

    private var amount: Binding<Int> {
        Binding(get: { draft.amount(drill.id) }, set: { draft.set($0, drillID: drill.id) })
    }

    private var onTarget: Binding<Int> {
        Binding(get: { draft.onTarget(drill.id) ?? 0 }, set: { draft.setOnTarget($0, drillID: drill.id) })
    }

    private func percent(_ target: Int) -> String {
        let shots = draft.amount(drill.id)
        return shots > 0 ? "\(Int((Double(target) / Double(shots) * 100).rounded()))%" : ""
    }
}

/// Plain-language totals for practice.
enum PracticeSummary {
    /// "120 shots (64% on target) · 15 min stickhandling · 40 passes", or nil when there's nothing.
    static func line(_ totals: PracticeTotals, byKind: [PracticeKind: PracticeTotals]? = nil) -> String? {
        var parts: [String] = []
        if totals.shots > 0 {
            parts.append(totals.accuracy.map { "\(totals.shots.formatted()) shots (\(Int(($0 * 100).rounded()))% on target)" }
                         ?? "\(totals.shots.formatted()) shots")
        }
        if totals.minutes > 0 {
            let minutes = max(totals.wholeMinutes, 1)
            let hands = byKind?[.stickhandling]?.minutes ?? totals.minutes
            parts.append(hands >= totals.minutes ? "\(minutes) min stickhandling" : "\(minutes) min")
        }
        if totals.reps > 0 { parts.append("\(totals.reps.formatted()) reps") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
