import SwiftUI
import LaxPocketCore

/// A coach's rosters, with how each athlete's week is going. Read from the cloud each time it opens; nothing about the
/// athletes is kept on this iPhone.
struct CoachingView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.appTheme) private var theme
    /// When Coaching is the whole app (a coach with no athletes of their own), it also opens Cloud sync.
    var showsSettings = false
    /// For a parent who also coaches: back to their own athletes.
    var onShowFamily: (() -> Void)?
    @State private var rosters: [CoachRoster] = []
    @State private var isLoading = true
    @State private var message: String?
    @State private var showNew = false
    @State private var showSettings = false
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: "Coaching")
                    Text("How each athlete's week is going. Pull down to refresh.")
                        .font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                }

                if let message {
                    Card { Text(message).font(.system(size: 14)).foregroundStyle(.red) }
                }

                if isLoading && rosters.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else if rosters.isEmpty {
                    Card {
                        Text("Make a roster for your team or your clients, then send its code to each family. A parent enters it in Cloud sync → Join with a code and picks their athlete.")
                            .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(rosters) { roster in
                    rosterSection(roster)
                }

                Button { showNew = true } label: {
                    Label("New roster", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                .padding(.top, 8)

                Text("Each roster is for one sport, and you see only the athlete's profile for it. Coaches see training and events (and wall ball in lacrosse); mental coaches see the mental game too. Never the budget, height and weight, or other sports.")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsSettings {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Cloud sync and account")
                }
            }
            if let onShowFamily {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onShowFamily) { Label("My family", systemImage: "chevron.left") }
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNew, onDismiss: { Task { await load() } }) { NewRosterView() }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                CloudSyncView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            now = Date()
            rosters = try await cloud.coachWorkspace()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    @ViewBuilder
    private func rosterSection(_ roster: CoachRoster) -> some View {
        SectionHeader(title: roster.name) {
            NavigationLink { RosterManageView(roster: roster, onChange: { Task { await load() } }) } label: {
                Text("Code & athletes").font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(.top, 8)
        Text("\(roster.sport.title) · \(roster.kind.title) · \(roster.athletes.count) athlete\(roster.athletes.count == 1 ? "" : "s")")
            .font(.system(size: 12)).foregroundStyle(AppTheme.caption)

        if roster.athletes.isEmpty {
            Card {
                Text(roster.joinCode.map { "Nobody yet. Send families the code \(InviteRow.displayCode($0))." }
                     ?? "Nobody yet, and the roster is closed. Open it in Code & athletes.")
                    .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
            }
        } else {
            Card(padding: 0) {
                ForEach(Array(roster.athletes.enumerated()), id: \.element.id) { index, athlete in
                    NavigationLink { CoachAthleteView(athlete: athlete, now: now) } label: {
                        CoachAthleteRow(athlete: athlete, week: athlete.week(now: now))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    if index < roster.athletes.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                }
            }
        }
    }
}

/// One athlete in a roster: hours against their goal, load, wall ball and anything worth a look.
struct CoachAthleteRow: View {
    @Environment(\.appTheme) private var theme
    let athlete: CoachAthlete
    let week: CoachWeek

    var body: some View {
        let profile = athlete.data.profile
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.firstName.isEmpty ? "Athlete" : profile.firstName)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(details(profile)).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                Spacer()
                Text("\(Formatters.hours(week.hours.total)) / \(Formatters.hours(week.goalHours)) h")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.ink2)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.chevron)
            }
            StackedHoursBar(hours: week.hours, goal: week.goalHours, height: 8)
            HStack(spacing: 6) {
                if let ratio = week.loadRatio, let zone = week.zone {
                    Pill(text: "Load \(String(format: "%.2f", ratio)) · \(zone.title)",
                         background: zone == .high ? theme.accentTint : AppTheme.background,
                         foreground: zone == .high ? theme.accentText : AppTheme.muted)
                }
                if week.wallball.total > 0 {
                    Pill(text: "Wall ball \(week.wallball.total)", background: AppTheme.background, foreground: AppTheme.muted)
                }
                ForEach(week.flags.filter { $0 != .highLoad }, id: \.self) { flag in
                    Pill(text: flag.title, background: theme.accentTint, foreground: theme.accentText)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func details(_ profile: AthleteProfile) -> String {
        [profile.classYear.map { "’\(String($0 % 100))" }, profile.positions.isEmpty ? nil : profile.positions]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// What a coach sees of one athlete: the week, recent training and wall ball, events, and the mental game for a
/// mental coach. Read only.
struct CoachAthleteView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL
    let athlete: CoachAthlete
    let now: Date

    var body: some View {
        let data = athlete.data
        let week = athlete.week(now: now)
        let recent = data.sessions.filter { $0.date <= now && $0.date >= now.addingTimeInterval(-14 * 86_400) }.sorted { $0.date > $1.date }
        let upcoming = Array(Season.upcoming(data.events, from: now).prefix(3))
        let results = Array(Season.results(data.events).prefix(3))

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: data.profile.firstName.isEmpty ? "Athlete" : data.profile.firstName)
                    let details = [data.profile.positions, data.profile.level].filter { !$0.isEmpty }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                    }
                }

                Card(padding: 20, radius: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This week").font(.system(size: 15, weight: .semibold))
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(Formatters.hours(week.hours.total)) h").font(.display(40)).foregroundStyle(theme.primary)
                            Text("of \(Formatters.hours(week.goalHours)) h goal").font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                        }
                        StackedHoursBar(hours: week.hours, goal: week.goalHours)
                        if let ratio = week.loadRatio, let zone = week.zone {
                            Text("Load \(String(format: "%.2f", ratio)) against the 4 weeks before. \(Workload.advice(for: zone))")
                                .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(week.flags, id: \.self) { flag in
                            Label(flag.title, systemImage: "exclamationmark.circle").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accentText)
                        }
                    }
                }

                if data.profile.sport.hasWallball {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wall ball this week").font(.system(size: 15, weight: .semibold))
                                Text("Right \(week.wallball.right) · left \(week.wallball.left) · both \(week.wallball.both)")
                                    .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(week.wallball.total)").font(.display(28)).foregroundStyle(AppTheme.ink)
                                Text(week.wallballStreak > 0 ? "\(week.wallballStreak)-day streak" : "No streak")
                                    .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                            }
                        }
                    }
                }

                SectionHeader(title: "Last two weeks").padding(.top, 6)
                if recent.isEmpty {
                    Card { Text("No training logged.").font(.system(size: 14)).foregroundStyle(AppTheme.ink2) }
                } else {
                    Card(padding: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                            VStack(alignment: .leading, spacing: 0) {
                                SessionRow(session: session, programName: data.program(id: session.programID)?.name ?? session.category.title)
                                if session.category == .mental && !session.notes.isEmpty {
                                    Text(session.notes).font(.system(size: 13)).foregroundStyle(AppTheme.ink2).padding(.bottom, 12)
                                }
                            }
                            .padding(.horizontal, 14)
                            if index < recent.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }

                if !upcoming.isEmpty {
                    SectionHeader(title: "Up next").padding(.top, 6)
                    Card(padding: 0) {
                        ForEach(upcoming) { event in UpcomingRow(event: event).padding(.horizontal, 16) }
                    }
                }

                if !results.isEmpty {
                    SectionHeader(title: "Recent games").padding(.top, 6)
                    ForEach(results) { event in resultCard(event) }
                }

                if data.canRead(.mental) {
                    mentalSection(data)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultCard(_ event: SeasonEvent) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(event.opponent.map { "vs \($0)" } ?? event.title).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let our = event.ourScore, let their = event.theirScore {
                        Text("\(event.outcome?.letter ?? "") \(our)–\(their)").font(.system(size: 15, weight: .bold)).foregroundStyle(theme.primary)
                    }
                }
                Text(event.date.formatted(.dateTime.weekday(.abbreviated).month().day())).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                if let stats = event.stats {
                    Text(stats.summaryLine).font(.system(size: 13)).foregroundStyle(AppTheme.ink2)
                }
                if let reflection = event.reflection {
                    if !reflection.wentWell.isEmpty { Text("Went well: \(reflection.wentWell)").font(.system(size: 13)).foregroundStyle(AppTheme.ink2) }
                    if !reflection.workOn.isEmpty { Text("Work on: \(reflection.workOn)").font(.system(size: 13)).foregroundStyle(AppTheme.ink2) }
                    if !reflection.coachFeedback.isEmpty {
                        Text("Coach: \(reflection.coachFeedback)").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mentalSection(_ data: AppData) -> some View {
        SectionHeader(title: "Mental game").padding(.top, 6)
        if data.docs.isEmpty && data.lockedDocs.isEmpty {
            Card { Text("No documents shared.").font(.system(size: 14)).foregroundStyle(AppTheme.ink2) }
        }
        ForEach(data.docs.sorted { $0.updatedAt > $1.updatedAt }) { doc in
            Button { openURL(doc.url) } label: {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            Text("\(doc.folder.title) · \(doc.updatedAt.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                        }
                        Spacer()
                        if doc.visibility == .locked {
                            Image(systemName: "lock.open").foregroundStyle(AppTheme.muted).accessibilityLabel("Locked; shared with you")
                        }
                        Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(AppTheme.chevron)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        if !data.lockedDocs.isEmpty {
            Text("\(data.lockedDocs.count) locked document\(data.lockedDocs.count == 1 ? "" : "s"). \(data.profile.firstName) can let you open them from their own login.")
                .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
        }
    }
}

/// A roster's code, name and athletes.
struct RosterManageView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let roster: CoachRoster
    var onChange: () -> Void
    @State private var name = ""
    @State private var code: String??
    @State private var removed: Set<UUID> = []
    @State private var message: String?
    @State private var confirmDelete = false

    private var currentCode: String? { code ?? roster.joinCode }

    var body: some View {
        Form {
            Section {
                if let currentCode {
                    Text(InviteRow.displayCode(currentCode))
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                    ShareLink(item: instructions(currentCode)) { Label("Send the code", systemImage: "square.and.arrow.up") }
                    Button("New code") { setCode(open: true) }
                    Button("Close to new athletes", role: .destructive) { setCode(open: false) }
                } else {
                    Text("Closed: no new athletes can join.").foregroundStyle(AppTheme.muted)
                    Button("Open with a new code") { setCode(open: true) }
                }
            } header: {
                Text("Join code")
            } footer: {
                Text("A parent enters the code and picks their athlete's \(roster.sport.title.lowercased()) profile; that's their OK for you to see \(roster.kind == .team ? "training and events" : "training, events and the mental game"). A new code stops the old one working.")
            }

            Section("Name") {
                TextField("Roster name", text: $name)
                    .onSubmit(rename)
                if name.trimmingCharacters(in: .whitespaces) != roster.name {
                    Button("Save name", action: rename).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                let athletes = roster.athletes.filter { !removed.contains($0.id) }
                if athletes.isEmpty { Text("Nobody yet.").foregroundStyle(AppTheme.muted) }
                ForEach(athletes) { athlete in
                    Text(athlete.data.profile.firstName.isEmpty ? "Athlete" : athlete.data.profile.firstName)
                        .swipeActions {
                            Button("Remove", role: .destructive) { remove(athlete) }
                        }
                }
            } header: {
                Text("Athletes")
            } footer: {
                Text("Swipe to take an athlete off. Their family can also take them off.")
            }

            Section {
                Button("Delete roster", role: .destructive) { confirmDelete = true }
            }

            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle(roster.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if name.isEmpty { name = roster.name } }
        .confirmationDialog("Delete \(roster.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete roster", role: .destructive) {
                run {
                    try await cloud.deleteRoster(roster.id)
                    onChange()
                    dismiss()
                }
            }
        } message: {
            Text("You stop seeing every athlete on it. Their data stays with their families.")
        }
    }

    private func instructions(_ code: String) -> String {
        "Add your athlete to \(roster.name) on SportsPocket: in Theme & settings → Cloud sync, tap Join with a code and enter \(InviteRow.displayCode(code)). "
            + "It's for your athlete's \(roster.sport.title.lowercased()) profile. Your coach will see: \(roster.kind.sharingSummary(for: roster.sport))"
    }

    private func setCode(open: Bool) {
        run {
            code = .some(try await cloud.resetRosterCode(roster.id, open: open))
            onChange()
        }
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != roster.name else { return }
        run {
            try await cloud.renameRoster(roster.id, to: trimmed)
            onChange()
        }
    }

    private func remove(_ athlete: CoachAthlete) {
        run {
            try await cloud.removeFromRoster(roster.id, athlete: athlete.id)
            removed.insert(athlete.id)
            onChange()
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        message = nil
        Task {
            do {
                try await action()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct NewRosterView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: RosterKind = .team
    @State private var sport: Sport = .lacrosse
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. U15 Girls", text: $name)
                    Picker("Sport", selection: $sport) {
                        ForEach(Sport.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Kind", selection: $kind) {
                        ForEach(RosterKind.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Only athletes' \(sport.title.lowercased()) profiles can join. You'll see: \(kind.sharingSummary(for: sport))")
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New roster")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if cloud.account?.kind == .mentalCoach { kind = .mental } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Create", action: create).fontWeight(.bold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() {
        isWorking = true
        message = nil
        Task {
            do {
                try await cloud.createRoster(name: name.trimmingCharacters(in: .whitespaces), kind: kind, sport: sport)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
