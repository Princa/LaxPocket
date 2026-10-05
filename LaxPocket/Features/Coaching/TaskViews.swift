import SwiftUI
import LaxPocketCore

/// A coach's task as it stands now: what it asks for, progress from what's logged, and a tick for the family.
struct AssignmentStatusRow: View {
    @Environment(\.appTheme) private var theme
    let status: AssignmentStatus
    /// Who it's from, on the family's screens.
    var showsCoach = true
    /// Nil: read only (a coach's view).
    var onTick: ((Bool) -> Void)?

    var body: some View {
        let assignment = status.assignment
        HStack(alignment: .top, spacing: 12) {
            if let onTick {
                Button { onTick(!status.markedDone) } label: {
                    Image(systemName: status.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(status.isDone ? theme.primary : AppTheme.chevron)
                }
                .buttonStyle(.plain)
                .disabled(status.reachedTarget && !status.markedDone)
                .accessibilityLabel(status.markedDone ? "Mark not done" : "Mark done")
            } else {
                Image(systemName: status.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(status.isDone ? theme.primary : AppTheme.chevron)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                    .strikethrough(status.isDone, color: AppTheme.muted)
                Text(caption).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                if assignment.kind != .check {
                    ProgressView(value: status.fraction).tint(status.isDone ? theme.primary : theme.accentText)
                }
                if !assignment.notes.isEmpty {
                    Text(assignment.notes).font(.system(size: 13)).foregroundStyle(AppTheme.ink2).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            Text(status.progressText).font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let assignment = status.assignment
        var parts = [assignment.summary()]
        if showsCoach, !assignment.coachName.isEmpty { parts.append(assignment.coachName) }
        if assignment.schedule == .once, !status.isDone, let due = assignment.dueOn, DayKey(Date()) > due { parts.append("Overdue") }
        return parts.joined(separator: " · ")
    }
}

/// Coaches' notes on a game, on the family's game page.
struct CoachNotesCard: View {
    let notes: [CoachNote]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(notes, id: \.coachID) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“\(note.note)”").font(.system(size: 15)).foregroundStyle(AppTheme.ink)
                        Text("\(note.coachName.isEmpty ? "Coach" : note.coachName) · \(note.updatedAt.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                    }
                }
            }
        }
    }
}

/// A coach gives a task to a roster or one athlete on it, or changes one.
struct AssignmentEditorView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let roster: CoachRoster
    var existing: Assignment?
    var onSaved: () -> Void
    @State private var title = ""
    @State private var notes = ""
    @State private var kind: AssignmentKind = .wallball
    @State private var schedule: AssignmentSchedule = .daily
    @State private var athleteID: UUID?
    @State private var reps = 200
    @State private var minutes = 60
    @State private var category: SessionCategory?
    @State private var startsOn = Date()
    @State private var dueOn = Date().addingTimeInterval(7 * 86_400)
    @State private var hasEnd = false
    @State private var endsOn = Date().addingTimeInterval(28 * 86_400)
    @State private var isWorking = false
    @State private var message: String?

    private var categories: [SessionCategory] {
        roster.kind == .mental ? SessionCategory.allCases : SessionCategory.allCases.filter { $0 != .mental }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, e.g. Left-hand wall ball", text: $title)
                    TextField("Notes for the athlete (optional)", text: $notes, axis: .vertical).lineLimit(2...5)
                    Picker("For", selection: $athleteID) {
                        Text("Everyone on \(roster.name)").tag(UUID?.none)
                        ForEach(roster.athletes) { Text($0.data.profile.firstName).tag(Optional($0.id)) }
                    }
                }

                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(AssignmentKind.allCases) { Text($0.title).tag($0) }
                    }
                    switch kind {
                    case .wallball:
                        Stepper("\(reps) reps", value: $reps, in: 10...5_000, step: 10)
                    case .training:
                        Stepper(AssignmentStatus.duration(minutes), value: $minutes, in: 15...3_000, step: 15)
                        Picker("Counts", selection: $category) {
                            Text("Any training").tag(SessionCategory?.none)
                            ForEach(categories) { Text($0.title).tag(Optional($0)) }
                        }
                    case .check:
                        EmptyView()
                    }
                } footer: {
                    Text(kind == .check ? "The athlete or a parent ticks it off." : "Ticks itself off once the athlete's log reaches it; they can also tick it by hand.")
                }

                Section("How often") {
                    Picker("Schedule", selection: $schedule) {
                        ForEach(AssignmentSchedule.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Starts", selection: $startsOn, displayedComponents: .date)
                    if schedule == .once {
                        DatePicker("Due", selection: $dueOn, in: startsOn..., displayedComponents: .date)
                    } else {
                        Toggle("Ends", isOn: $hasEnd)
                        if hasEnd { DatePicker("Last day", selection: $endsOn, in: startsOn..., displayedComponents: .date) }
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle(existing == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: load)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(existing == nil ? "Give" : "Save", action: save).fontWeight(.bold)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func load() {
        guard let a = existing, title.isEmpty else { return }
        title = a.title
        notes = a.notes
        kind = a.kind
        schedule = a.schedule
        athleteID = a.profileID
        reps = a.targetReps ?? reps
        minutes = a.targetMinutes ?? minutes
        category = a.category
        startsOn = a.startsOn.date()
        if let due = a.dueOn { dueOn = due.date() }
        if let end = a.endsOn { hasEnd = true; endsOn = end.date() }
    }

    private func save() {
        let assignment = Assignment(
            id: existing?.id ?? UUID(), rosterID: roster.id, profileID: athleteID, kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: schedule, startsOn: DayKey(startsOn), dueOn: schedule == .once ? DayKey(max(dueOn, startsOn)) : nil,
            endsOn: schedule != .once && hasEnd ? DayKey(max(endsOn, startsOn)) : nil,
            targetReps: kind == .wallball ? reps : nil, targetMinutes: kind == .training ? minutes : nil,
            category: kind == .training ? category : nil)
        isWorking = true
        message = nil
        Task {
            do {
                try await cloud.saveAssignment(assignment)
                onSaved()
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// One task on a roster: who it's for and who's done it for the current day, week or span.
struct AssignmentDetailView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let roster: CoachRoster
    let assignment: Assignment
    let now: Date
    var onChange: () -> Void
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        let athletes = roster.athletes.filter { assignment.isFor($0.id) }
        Form {
            Section {
                Text(assignment.summary())
                if !assignment.notes.isEmpty { Text(assignment.notes).foregroundStyle(AppTheme.ink2) }
            }
            Section {
                if athletes.isEmpty { Text("Nobody on the roster yet.").foregroundStyle(AppTheme.muted) }
                ForEach(athletes) { athlete in
                    if let status = athlete.data.assignmentStatus(assignment, now: now) {
                        LabeledContent {
                            Text(status.progressText).foregroundStyle(status.isDone ? AppTheme.ink : AppTheme.muted)
                        } label: {
                            Label(athlete.data.profile.firstName, systemImage: status.isDone ? "checkmark.circle.fill" : "circle")
                        }
                    } else {
                        LabeledContent(athlete.data.profile.firstName, value: "Not running now")
                    }
                }
            } header: {
                Text(periodTitle)
            }
            Section {
                Button("Edit task") { showEdit = true }
                Button("Delete task", role: .destructive) { confirmDelete = true }
            }
            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle(assignment.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            AssignmentEditorView(roster: roster, existing: assignment, onSaved: onChange)
        }
        .confirmationDialog("Delete \(assignment.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                Task {
                    do {
                        try await cloud.deleteAssignment(assignment.id)
                        onChange()
                        dismiss()
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("It goes from every athlete's phone at their next sync.")
        }
    }

    private var periodTitle: String {
        switch assignment.schedule {
        case .daily: return "Today"
        case .weekly: return "This week"
        case .once: return "By the due date"
        }
    }
}

/// A coach writes (or clears) their note on an athlete's game.
struct CoachNoteEditor: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let athleteName: String
    let event: SeasonEvent
    let athleteID: UUID
    @State var note: String
    /// Gets the note as saved; empty when it was removed.
    var onSaved: (String) -> Void
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What went well, what to work on", text: $note, axis: .vertical).lineLimit(4...10)
                } footer: {
                    Text("\(athleteName) and their parents see it on the game. Leave it empty to remove your note.")
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle(event.opponent.map { "vs \($0)" } ?? event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Save", action: save).fontWeight(.bold)
                    }
                }
            }
        }
    }

    private func save() {
        isWorking = true
        message = nil
        Task {
            do {
                try await cloud.saveCoachNote(event: event.id, athlete: athleteID, note: note)
                onSaved(note.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
