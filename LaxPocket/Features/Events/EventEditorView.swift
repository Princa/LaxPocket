import SwiftUI
import LaxPocketCore

/// Adds or edits a game, tournament, showcase or camp: when and where, the result and stat line,
/// pre-game goals, the post-game reflection, video links and the prep checklist.
struct EventEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let original: SeasonEvent
    private let onDelete: () -> Void

    @State private var kind: EventKind
    @State private var title: String
    @State private var team: String
    @State private var opponent: String
    @State private var location: String
    @State private var date: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var dateIsTentative: Bool
    @State private var played: Bool
    @State private var ourScore: Int
    @State private var theirScore: Int
    @State private var hasStats: Bool
    @State private var stats: GameStats
    @State private var hasReflection: Bool
    @State private var reflection: Reflection
    @State private var focus: [FocusGoal]
    @State private var videos: [VideoDraft]
    @State private var checklist: [ChecklistItem]
    @State private var confirmDelete = false

    private struct VideoDraft: Identifiable {
        var id: UUID
        var title: String
        var link: String
        var durationText: String
    }

    /// Pass a new `SeasonEvent` to add it, or one from the store to edit it.
    init(event: SeasonEvent, onDelete: @escaping () -> Void = {}) {
        original = event
        self.onDelete = onDelete
        _kind = State(initialValue: event.kind)
        let autoTitle = event.opponent.map { "vs \($0)" }
        _title = State(initialValue: event.title == autoTitle ? "" : event.title)
        _team = State(initialValue: event.team)
        _opponent = State(initialValue: event.opponent ?? "")
        _location = State(initialValue: event.location)
        _date = State(initialValue: event.date)
        _hasEndDate = State(initialValue: event.endDate != nil)
        _endDate = State(initialValue: event.endDate ?? event.date)
        _dateIsTentative = State(initialValue: event.dateIsTentative)
        _played = State(initialValue: event.hasResult)
        _ourScore = State(initialValue: event.ourScore ?? 0)
        _theirScore = State(initialValue: event.theirScore ?? 0)
        _hasStats = State(initialValue: event.stats != nil)
        _stats = State(initialValue: event.stats ?? GameStats())
        _hasReflection = State(initialValue: event.reflection != nil)
        _reflection = State(initialValue: event.reflection ?? Reflection())
        _focus = State(initialValue: event.focus)
        _videos = State(initialValue: event.videos.map { VideoDraft(id: $0.id, title: $0.title, link: $0.url.absoluteString, durationText: $0.durationText) })
        _checklist = State(initialValue: event.checklist)
    }

    /// A blank game a day from now, for the add button.
    static func newEvent(team: String = "") -> SeasonEvent {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return SeasonEvent(kind: .game, title: "", team: team, date: start)
    }

    private var isNew: Bool { !store.data.events.contains { $0.id == original.id } }
    private var canScore: Bool { kind == .game || kind == .tournament }
    private var athlete: String {
        let name = store.profile.firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Athlete" : name
    }

    /// Team programs first, then teams already used on other events.
    private var teamSuggestions: [String] {
        var names = store.data.programs.filter { $0.group == .teams }.map(\.name)
        for event in store.data.events where !names.contains(event.team) && !event.team.isEmpty { names.append(event.team) }
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                whenSection
                if canScore {
                    resultSection
                    if played { statsSection }
                }
                focusSection
                if canScore && played { reflectionSection }
                videosSection
                checklistSection
                if !isNew {
                    Section {
                        Button("Delete event", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Add event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.bold) }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteEvent(original.id)
                    dismiss()
                    onDelete()
                }
            } message: {
                Text("Removes the event with its result, goals, reflection, videos and checklist.")
            }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section {
            Picker("Type", selection: $kind) {
                ForEach(EventKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("Team, e.g. Club 2031", text: $team)
                if !teamSuggestions.isEmpty {
                    Menu {
                        ForEach(teamSuggestions, id: \.self) { name in Button(name) { team = name } }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                    .accessibilityLabel("Choose a team")
                }
            }
            if kind == .game {
                TextField("Opponent", text: $opponent)
            }
            TextField(kind == .game ? "Title (optional)" : "Title, e.g. Fall showcase", text: $title)
            TextField("Location", text: $location)
        }
    }

    private var whenSection: some View {
        Section {
            DatePicker(dateIsTentative ? "Month" : "Starts", selection: $date,
                       displayedComponents: dateIsTentative ? [.date] : [.date, .hourAndMinute])
            Toggle("Runs over several days", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("Ends", selection: $endDate, in: date..., displayedComponents: dateIsTentative ? [.date] : [.date, .hourAndMinute])
            }
            Toggle("Dates not confirmed yet", isOn: $dateIsTentative)
        } header: {
            Text("When")
        } footer: {
            if dateIsTentative { Text("Only the month is shown, marked “TBC”.") }
        }
    }

    private var resultSection: some View {
        Section("Result") {
            Toggle("Final score", isOn: $played)
            if played {
                Stepper(value: $ourScore, in: 0...99) { LabeledContent("Our team", value: "\(ourScore)") }
                Stepper(value: $theirScore, in: 0...99) {
                    LabeledContent(opponent.trimmingCharacters(in: .whitespaces).isEmpty ? "Opponent" : opponent, value: "\(theirScore)")
                }
            }
        }
    }

    private var statsSection: some View {
        Section {
            Toggle("\(athlete)’s stat line", isOn: $hasStats)
            if hasStats {
                statStepper("Goals", value: $stats.goals)
                statStepper("Assists", value: $stats.assists)
                statStepper("Shots", value: $stats.shots)
                statStepper("Ground balls", value: $stats.groundBalls)
                statStepper("Draw controls", value: $stats.drawControls)
                statStepper("Caused turnovers", value: $stats.causedTurnovers)
            }
        }
    }

    private var focusSection: some View {
        Section {
            ForEach($focus) { $goal in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Goal, e.g. Win 3+ draw controls", text: $goal.text, axis: .vertical)
                    HStack {
                        Picker("Outcome", selection: $goal.outcome) {
                            ForEach(FocusOutcome.allCases, id: \.self) { Text($0 == .pending ? "Not rated" : $0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        TextField("Note", text: $goal.note)
                    }
                    .font(.system(size: 14))
                }
                .padding(.vertical, 2)
            }
            .onDelete { focus.remove(atOffsets: $0) }
            Button { focus.append(FocusGoal(text: "")) } label: { Label("Add a goal", systemImage: "plus") }
        } header: {
            Text("Pre-game focus")
        } footer: {
            Text("Two or three things to focus on. Rate them after the game.")
        }
    }

    private var reflectionSection: some View {
        Section("Post-game reflection") {
            Toggle("Add a reflection", isOn: $hasReflection)
            if hasReflection {
                Picker("Self-rating", selection: $reflection.selfRating) {
                    Text("Not rated").tag(Int?.none)
                    ForEach(1...10, id: \.self) { Text("\($0) / 10").tag(Int?.some($0)) }
                }
                TextField("What went well", text: $reflection.wentWell, axis: .vertical)
                    .lineLimit(2...5)
                TextField("What to work on", text: $reflection.workOn, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Coach feedback", text: $reflection.coachFeedback, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
    }

    private var videosSection: some View {
        Section {
            ForEach($videos) { $video in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title, e.g. Highlights", text: $video.title)
                    TextField("Link", text: $video.link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14))
                    TextField("Length, e.g. 2:14 (optional)", text: $video.durationText)
                        .font(.system(size: 14))
                }
                .padding(.vertical, 2)
            }
            .onDelete { videos.remove(atOffsets: $0) }
            Button { videos.append(VideoDraft(id: UUID(), title: "", link: "", durationText: "")) } label: {
                Label("Add a video link", systemImage: "plus")
            }
        } header: {
            Text("Video")
        } footer: {
            Text("Links to game film or highlights, e.g. on YouTube or Hudl.")
        }
    }

    private var checklistSection: some View {
        Section("Prep checklist") {
            ForEach($checklist) { $item in
                HStack(spacing: 10) {
                    Button { $item.done.wrappedValue.toggle() } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.done ? "Done" : "Not done")
                    TextField("Item, e.g. Registration", text: $item.title)
                }
            }
            .onDelete { checklist.remove(atOffsets: $0) }
            Button { checklist.append(ChecklistItem(title: "")) } label: { Label("Add an item", systemImage: "plus") }
        }
    }

    private func statStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...99) { LabeledContent(label, value: "\(value.wrappedValue)") }
    }

    // MARK: - Save

    private func save() {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var event = original
        event.kind = kind
        event.team = clean(team).isEmpty ? kind.title : clean(team)
        event.opponent = kind == .game && !clean(opponent).isEmpty ? clean(opponent) : nil
        event.title = clean(title).isEmpty ? (event.opponent.map { "vs \($0)" } ?? kind.title) : clean(title)
        event.location = clean(location)
        event.date = date
        event.endDate = hasEndDate ? max(endDate, date) : nil
        event.dateIsTentative = dateIsTentative

        let hasScore = canScore && played
        event.ourScore = hasScore ? ourScore : nil
        event.theirScore = hasScore ? theirScore : nil
        event.stats = hasScore && hasStats ? stats : nil

        if hasScore && hasReflection {
            var updated = reflection
            updated.wentWell = clean(updated.wentWell)
            updated.workOn = clean(updated.workOn)
            updated.coachFeedback = clean(updated.coachFeedback)
            if updated.coachFeedback.isEmpty {
                updated.coachFeedbackDate = nil
            } else if updated.coachFeedback != original.reflection?.coachFeedback {
                updated.coachFeedbackDate = Date()
            }
            event.reflection = updated
        } else {
            event.reflection = nil
        }

        event.focus = focus.filter { !clean($0.text).isEmpty }
        event.videos = videos.compactMap { draft in
            MentalDoc.normalizedURL(from: draft.link).map {
                VideoLink(id: draft.id, title: clean(draft.title).isEmpty ? "Video" : clean(draft.title), url: $0, durationText: clean(draft.durationText))
            }
        }
        event.checklist = checklist.filter { !clean($0.title).isEmpty }
        store.saveEvent(event)
        dismiss()
    }
}
