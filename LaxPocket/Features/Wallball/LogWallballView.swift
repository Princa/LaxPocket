import SwiftUI
import LaxPocketCore

/// Logs a day's wall ball reps, or edits a session. Pick every drill with one tap and give them all the same reps,
/// or pick drills one by one and set each hand.
struct LogWallballView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The session being edited; nil for a new one.
    private let session: WallballSession?
    @State private var draft: WallballDraft
    @State private var date: Date
    @State private var minutes: Int
    @State private var notes: String
    @State private var showAddDrill = false
    @State private var confirmDelete = false

    static let quickReps = [10, 20, 25, 50, 100]

    init(session: WallballSession? = nil) {
        self.session = session
        _draft = State(initialValue: WallballDraft(sets: session?.sets ?? []))
        _date = State(initialValue: session?.date ?? Date())
        _minutes = State(initialValue: session?.minutes ?? 0)
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var isNew: Bool { session == nil }

    /// Drills offered: everything not hidden, plus hidden ones already in this session.
    private var drills: [WallballDrill] {
        store.data.wallballLibrary.filter { !$0.isHidden || draft.isPicked($0.id) }
    }

    /// The latest other session, to repeat.
    private var lastSession: WallballSession? {
        store.data.wallballSessions.filter { $0.id != session?.id && !$0.isChallenge }.max { $0.date < $1.date }
    }

    var body: some View {
        let library = drills
        let total = draft.total(in: library)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    quickCard(library)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Eyebrow(text: "Drills", color: AppTheme.caption)
                            Spacer()
                            Text("\(draft.pickedCount) of \(library.count) picked")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.caption)
                        }
                        Card(padding: 0, radius: 14) {
                            ForEach(Array(library.enumerated()), id: \.element.id) { index, drill in
                                DrillRepsRow(drill: drill, draft: $draft)
                                    .padding(.horizontal, 14)
                                if index < library.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 52) }
                            }
                        }
                        Button { showAddDrill = true } label: {
                            Label("Add a drill", systemImage: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
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
            .safeAreaInset(edge: .bottom) { saveBar(total) }
            .navigationTitle(isNew ? "Log wall ball" : session?.isChallenge == true ? "Edit challenge" : "Edit wall ball")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(total.total == 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $showAddDrill) {
                WallballDrillEditorView { drill in draft.pick(drill) }
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let session { store.deleteWallballSessions([session.id]) }
                    dismiss()
                }
            }
        }
    }

    // MARK: - Pieces

    private func quickCard(_ library: [WallballDrill]) -> some View {
        Card(padding: 14, radius: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        draft.pickAll(library.filter { !$0.isHidden })
                    } label: {
                        Label("Pick all", systemImage: "checklist")
                    }
                    .buttonStyle(QuickButtonStyle(color: theme.primary, filled: true))
                    .disabled(library.allSatisfy { $0.isHidden || draft.isPicked($0.id) })

                    Button { draft.clear() } label: { Label("Clear", systemImage: "xmark") }
                        .buttonStyle(QuickButtonStyle(color: theme.primary, filled: false))
                        .disabled(draft.isEmpty)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.isEmpty ? "Pick all, with the same reps for every hand" : "Same reps for every picked drill and hand")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.caption)
                    HStack(spacing: 6) {
                        ForEach(Self.quickReps, id: \.self) { reps in
                            Button("\(reps)") { applyAll(reps, library: library) }
                                .buttonStyle(QuickButtonStyle(color: theme.accent, filled: false, textColor: theme.accentText, expands: true))
                                .accessibilityLabel(draft.isEmpty ? "Pick all with \(reps) reps" : "Set every picked drill to \(reps) reps")
                        }
                    }
                }

                if isNew, let last = lastSession {
                    Button {
                        draft = WallballDraft(sets: last.sets)
                    } label: {
                        Label("Same as \(last.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(last.reps.total.formatted()) reps",
                              systemImage: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }
                    .foregroundStyle(theme.primary)
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
                Button { minutes = max(0, minutes - 5) } label: { stepIcon("minus") }
                    .disabled(minutes == 0)
                    .accessibilityLabel("Five minutes less")
                Text(minutes == 0 ? "Not noted" : "\(minutes) min")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(minutes == 0 ? AppTheme.caption : AppTheme.ink)
                    .frame(minWidth: 84)
                Button { minutes = min(240, minutes + 5) } label: { stepIcon("plus") }
                    .accessibilityLabel("Five minutes more")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider().overlay(AppTheme.line).padding(.leading, 14)
            TextField("Notes: what felt good, what to work on", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .padding(14)
        }
    }

    private func saveBar(_ total: HandReps) -> some View {
        VStack(spacing: 8) {
            Text(summary(total))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button(isNew ? "Save \(total.total.formatted()) reps" : "Save changes", action: save)
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                .disabled(total.total == 0)
                .opacity(total.total == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func summary(_ total: HandReps) -> String {
        guard total.total > 0 else { return "Pick drills to log reps" }
        var parts = ["\(draft.pickedCount) drill\(draft.pickedCount == 1 ? "" : "s")", "Right \(total.right)", "Left \(total.left)"]
        if total.both > 0 { parts.append("Both \(total.both)") }
        return parts.joined(separator: " · ")
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .frame(width: 36, height: 36)
            .background(AppTheme.background, in: Circle())
            .frame(width: 44, height: 44)
    }

    // MARK: - Actions

    private func applyAll(_ reps: Int, library: [WallballDrill]) {
        if draft.isEmpty {
            draft.pickAll(library.filter { !$0.isHidden }, reps: reps)
        } else {
            draft.setAll(reps)
        }
    }

    private func save() {
        let sets = draft.sets(in: drills)
        guard !sets.isEmpty else { return }
        var entry = session ?? WallballSession(date: date, sets: [])
        entry.date = date
        entry.sets = sets
        entry.minutes = minutes > 0 ? minutes : nil
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.saveWallballSession(entry)
        dismiss()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// One drill in the log: tap to pick it, then set reps for each hand.
private struct DrillRepsRow: View {
    @Environment(\.appTheme) private var theme
    let drill: WallballDrill
    @Binding var draft: WallballDraft

    var body: some View {
        let picked = draft.isPicked(drill.id)
        VStack(alignment: .leading, spacing: 10) {
            Button { draft.toggle(drill) } label: {
                HStack(spacing: 12) {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(picked ? theme.primary : AppTheme.border)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drill.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        if !picked || drill.hands == .together {
                            Text(picked ? "Both hands" : drill.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.caption)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if picked && drill.hands == .together {
                        RepStepper(value: binding(.both), color: theme.color(for: .both))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(drill.name)
            .accessibilityAddTraits(picked ? .isSelected : [])
            .accessibilityHint(picked ? "Removes the drill" : "Adds the drill")

            if picked && drill.hands == .each {
                HStack(spacing: 10) {
                    handStepper(.right)
                    Spacer(minLength: 0)
                    handStepper(.left)
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 12)
    }

    private func handStepper(_ hand: WallballHand) -> some View {
        HStack(spacing: 4) {
            Text(hand.letter)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.color(for: hand))
                .frame(width: 14)
                .accessibilityHidden(true)
            RepStepper(value: binding(hand), color: theme.color(for: hand))
                .accessibilityLabel("\(hand.title) hand reps")
        }
    }

    private func binding(_ hand: WallballHand) -> Binding<Int> {
        Binding(get: { draft.reps(drill.id, hand) }, set: { draft.set($0, drillID: drill.id, hand: hand) })
    }
}

/// Minus, a typed number, plus. Steps by 5.
struct RepStepper: View {
    @Binding var value: Int
    var color: Color
    var step = 5

    var body: some View {
        HStack(spacing: 2) {
            Button { value = max(0, value - step) } label: { icon("minus") }
                .disabled(value == 0)
                .accessibilityLabel("\(step) fewer")
            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.display(20))
                .foregroundStyle(value == 0 ? AppTheme.caption : AppTheme.ink)
                .frame(width: 48, height: 36)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button { value = min(WallballSet.repsRange.upperBound, value + step) } label: { icon("plus") }
                .accessibilityLabel("\(step) more")
        }
        .buttonStyle(.plain)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 36, height: 40)
            .contentShape(Rectangle())
    }
}

/// Small capsule button for quick actions in a card.
struct QuickButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let color: Color
    var filled: Bool
    var textColor: Color? = nil
    /// Shares a row's width with its neighbours.
    var expands = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .frame(maxWidth: expands ? .infinity : nil)
            .foregroundStyle(filled ? .white : (textColor ?? color))
            .background(filled ? color : AppTheme.card, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.6), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
