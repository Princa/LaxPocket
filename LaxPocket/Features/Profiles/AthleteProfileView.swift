import SwiftUI
import LaxPocketCore

/// The active athlete's profile: details, every club and team they play for, and height and weight.
struct AthleteProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var editingClub: ClubTarget?
    @State private var showLogBody = false
    @State private var showAddSport = false

    /// Which club the editor sheet is for; nil for a new one.
    private struct ClubTarget: Identifiable {
        let id = UUID()
        var program: Program?
    }

    var body: some View {
        let clubs = store.data.programs.filter { $0.group == .teams }
        let name = store.data.summary.displayName
        let sport = store.sport

        Form {
            Section {
                header
            }

            Section("Athlete") {
                TextField("First name", text: athleteBinding(\.firstName))
                    .textContentType(.givenName)
                TextField("Class of", value: athleteBinding(\.classYear), format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField(sport.positionsPrompt, text: binding(\.profile.positions))
                if sport == .hockey {
                    HockeyFields(shoots: binding(\.profile.shoots), playsGoal: binding(\.profile.playsGoal), level: binding(\.profile.level))
                }
                TextField("Mental coach's name", text: binding(\.profile.mentalCoachName))
            }

            sportsSection

            Section {
                ForEach(clubs) { club in
                    Button { editingClub = ClubTarget(program: club) } label: { clubRow(club) }
                        .buttonStyle(.plain)
                }
                Button { editingClub = ClubTarget() } label: {
                    Label("Add a club or team", systemImage: "plus")
                }
                if sport.hasNDTPTesting {
                    NDTPPicker(group: Binding(get: { store.profile.benchmarkGroup }, set: { group in store.update { $0.setNDTPGroup(group) } }))
                }
            } header: {
                Text("Clubs & teams")
            } footer: {
                Text("Add every \(sport.title.lowercased()) team \(name) plays for: \(sport.teamKinds). Each one shows up in Log session and when you add a game."
                     + (sport.hasNDTPTesting ? " Picking an NDTP age group adds NDTP as a team and scores combine results against that group's standards." : ""))
            }

            if store.data.canRead(.health) {
                Section("Height & weight") {
                    NavigationLink { HealthView() } label: {
                        LabeledContent("Latest", value: BodyTrends.summary(store.data.bodyMeasurements, units: store.profile.bodyUnits) ?? "Not logged")
                    }
                    Picker("Units", selection: binding(\.profile.bodyUnits)) {
                        ForEach(BodyUnits.allCases) { Text($0.title).tag($0) }
                    }
                    Button { showLogBody = true } label: {
                        Label("Log height & weight", systemImage: "plus")
                    }
                }
            }

            Section {
                NavigationLink { ProgramsView() } label: {
                    Label("Coaches, gyms & other programs", systemImage: "square.grid.2x2")
                }
            } footer: {
                Text("Season, weekly goal, budget and theme are in Theme & settings.")
            }
        }
        .navigationTitle("Athlete profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingClub) { target in ProgramEditorView(program: target.program, group: .teams) }
        .sheet(isPresented: $showLogBody) { LogMeasurementView(units: store.profile.bodyUnits) }
        .sheet(isPresented: $showAddSport) { NewProfileView(athlete: store.data) }
    }

    /// The athlete's sports: switch to another, or add one. Each sport is its own profile.
    @ViewBuilder
    private var sportsSection: some View {
        let sports = store.athleteSports
        let toAdd = store.sportsToAdd(for: store.data.id)
        if sports.count > 1 || !toAdd.isEmpty {
            Section {
                ForEach(sports) { summary in
                    Button { store.switchProfile(to: summary.id) } label: {
                        HStack {
                            Label(summary.sport.title, systemImage: summary.sport.symbolName)
                            Spacer()
                            if summary.id == store.data.id {
                                Text("Showing").foregroundStyle(AppTheme.muted)
                            }
                        }
                    }
                    .disabled(summary.id == store.data.id)
                }
                if !toAdd.isEmpty {
                    Button { showAddSport = true } label: {
                        Label("Add a sport", systemImage: "plus")
                    }
                }
            } header: {
                Text("Sports")
            } footer: {
                Text("Each sport is kept apart: its own training, games, budget, theme and coaches. The name and class year are the same in every sport.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProfileAvatar(summary: store.data.summary, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.data.summary.displayName).font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.ink)
                if !detailLine.isEmpty {
                    Text(detailLine).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Class of 2031 · Midfield · 5′4″ · 3 teams"
    private var detailLine: String {
        let p = store.profile
        var parts: [String] = []
        if let year = p.classYear { parts.append("Class of \(year)") }
        if !p.positions.isEmpty { parts.append(p.positions) }
        if !p.level.isEmpty { parts.append(p.level) }
        if let height = BodyTrends.heights(store.data.bodyMeasurements).last { parts.append(p.bodyUnits.formatHeight(height.value)) }
        let teams = store.data.programs.filter { $0.group == .teams }.count
        if teams > 0 { parts.append(teams == 1 ? "1 team" : "\(teams) teams") }
        return parts.joined(separator: " · ")
    }

    private func clubRow(_ club: Program) -> some View {
        HStack(spacing: 12) {
            Monogram(text: club.monogram, background: theme.primaryTint, foreground: theme.primary, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(club.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                if !club.detail.isEmpty {
                    Text(club.detail).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                }
            }
            Spacer()
            Text(activity(club)).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the team to edit")
    }

    /// "4 games · 12.5 h", from games entered for this team and sessions logged with it.
    private func activity(_ club: Program) -> String {
        let games = store.data.events.filter { $0.kind == .game && $0.team == club.name }.count
        let hours = store.data.hoursByProgram[club.id] ?? 0
        var parts: [String] = []
        if games > 0 { parts.append(games == 1 ? "1 game" : "\(games) games") }
        if hours > 0 { parts.append("\(Formatters.hours(hours)) h") }
        return parts.joined(separator: " · ")
    }

    /// For what's the same in every sport: the name and class year.
    private func athleteBinding<Value>(_ keyPath: WritableKeyPath<AthleteProfile, Value>) -> Binding<Value> {
        Binding(
            get: { store.profile[keyPath: keyPath] },
            set: { newValue in store.updateAthlete { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppData, Value>) -> Binding<Value> {
        Binding(
            get: { store.data[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
