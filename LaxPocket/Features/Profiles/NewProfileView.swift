import SwiftUI
import LaxPocketCore

/// Creates an athlete profile for one sport, or adds another sport for an athlete (`athlete`). Each sport profile keeps
/// its own sessions, results, events, budget, docs and height and weight; an athlete's sports share only their name.
struct NewProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The athlete to add a sport for; nil for a new athlete.
    var athlete: AppData?
    @State private var sport: Sport = .lacrosse
    @State private var firstName = ""
    @State private var classYear: Int?
    @State private var positions = ""
    /// Nil unless they're on an NDTP team.
    @State private var ndtpGroup: BenchmarkGroup?
    @State private var shoots: Handedness?
    @State private var playsGoal = false
    @State private var level = ""
    @State private var season = AthleteProfile.seasonLabel(for: Date())
    @State private var weeklyGoal = 12.0
    @State private var themeID = ThemeCatalog.defaultID
    @State private var bodyInput = BodyInput(units: .imperial)
    /// Names typed for the athlete's clubs and teams; blank ones are skipped.
    @State private var clubs: [String] = [""]
    @State private var didSetUp = false

    private var trimmedName: String { (athlete?.profile.firstName ?? firstName).trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The sports this can make: all of them for a new athlete, the ones the athlete doesn't play yet otherwise.
    private var sports: [Sport] { athlete.map { store.sportsToAdd(for: $0.id) } ?? Sport.allCases }

    var body: some View {
        let theme = AppTheme(palette: ThemeCatalog.palette(id: themeID))
        NavigationStack {
            Form {
                Section {
                    Picker("Sport", selection: $sport) {
                        ForEach(sports) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    if let athlete {
                        Text("\(athlete.summary.displayName)’s \(sport.title.lowercased()) is kept apart from their other sports: its own training, games, budget and coaches. The family on \(athlete.summary.displayName) can see it too.")
                    }
                }

                Section {
                    if let athlete {
                        LabeledContent("Athlete", value: athlete.summary.displayName)
                    } else {
                        TextField("First name", text: $firstName)
                            .textContentType(.givenName)
                        TextField("Class of", value: $classYear, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                    }
                    TextField(sport.positionsPrompt, text: $positions)
                    if sport == .hockey {
                        HockeyFields(shoots: $shoots, playsGoal: $playsGoal, level: $level)
                    }
                } header: {
                    Text("Athlete")
                }

                Section {
                    ForEach(clubs.indices, id: \.self) { index in
                        TextField(index == 0 ? sport.teamPrompts.first : sport.teamPrompts.more, text: $clubs[index])
                    }
                    Button { clubs.append("") } label: {
                        Label("Add another team", systemImage: "plus")
                    }
                    if sport.hasNDTPTesting {
                        NDTPPicker(group: $ndtpGroup)
                    }
                } header: {
                    Text("Clubs & teams")
                } footer: {
                    Text(sport.hasNDTPTesting
                         ? "Optional. Add every team they play for. On an NDTP team, NDTP is added as a team and combine results are scored against that age group's standards. Coaches, gyms and more teams can be added later from the profile."
                         : "Optional. Add every team they play for: \(sport.teamKinds). Coaches, gyms and more teams can be added later from the profile.")
                }

                BodyInputFields(input: $bodyInput, footer: "Optional. Saved as today’s measurement; log more from Home → Health to track growth.")

                Section("Season") {
                    TextField("Season", text: $season)
                    Stepper(value: $weeklyGoal, in: 1...30, step: 0.5) {
                        LabeledContent("Weekly goal", value: "\(Formatters.hours(weeklyGoal)) h")
                    }
                }

                Section {
                    Picker("Theme", selection: $themeID) {
                        ForEach(ThemeCatalog.all) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("Everything here can be changed later in Theme & settings.")
                }
            }
            .navigationTitle(athlete == nil ? "New athlete" : "Add a sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).fontWeight(.bold)
                        .disabled(trimmedName.isEmpty || bodyInput.hasError || !sports.contains(sport))
                }
            }
            .onAppear(perform: setUp)
        }
        .tint(theme.primary)
    }

    /// For another sport: the athlete's units, the first sport they don't have, and a theme their other sports don't use.
    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        guard let athlete else { return }
        sport = sports.first ?? .hockey
        bodyInput = BodyInput(units: athlete.profile.bodyUnits)
        let used = store.index.sportProfiles(of: athlete.id).map(\.themeID)
        themeID = AppData.suggestedTheme(besides: used)
    }

    private func create() {
        var data: AppData
        if let athlete {
            data = athlete.addingSport(sport, themeID: themeID)
        } else {
            data = AppData.newProfile(AthleteProfile(firstName: trimmedName, classYear: classYear, positions: "", season: season,
                                                     bodyUnits: bodyInput.units, sport: sport),
                                      themeID: themeID)
        }
        data.profile.positions = positions.trimmingCharacters(in: .whitespacesAndNewlines)
        data.profile.weeklyGoalHours = weeklyGoal
        data.profile.season = season.trimmingCharacters(in: .whitespacesAndNewlines)
        data.profile.bodyUnits = bodyInput.units
        if sport == .hockey {
            data.profile.shoots = shoots
            data.profile.playsGoal = playsGoal
            data.profile.level = level.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for club in clubs {
            let name = club.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            data.programs.append(Program(id: Program.newID(), name: name, detail: "", group: .teams, sessionCategory: .team,
                                         monogram: Program.suggestedMonogram(for: name)))
        }
        if sport.hasNDTPTesting { data.setNDTPGroup(ndtpGroup) }
        if !bodyInput.isBlank && !bodyInput.hasError {
            data.bodyMeasurements = [bodyInput.applied(to: BodyMeasurement(date: Date()))]
        }
        store.createProfile(data)
        dismiss()
    }
}

/// Hockey's profile details: which way they shoot, goalie or not, and their level.
struct HockeyFields: View {
    @Binding var shoots: Handedness?
    @Binding var playsGoal: Bool
    @Binding var level: String

    var body: some View {
        Picker("Shoots", selection: $shoots) {
            Text("Not set").tag(Handedness?.none)
            ForEach(Handedness.allCases) { Text($0.title).tag(Handedness?.some($0)) }
        }
        Toggle("Goalie", isOn: $playsGoal)
        TextField("Level, e.g. U15 AA", text: $level)
    }
}

/// Whether the athlete is on an NDTP team, and in which age group. Off by default.
struct NDTPPicker: View {
    @Binding var group: BenchmarkGroup?

    var body: some View {
        Picker("NDTP team", selection: $group) {
            Text("None").tag(BenchmarkGroup?.none)
            ForEach(BenchmarkGroup.allCases) { Text($0.title).tag(BenchmarkGroup?.some($0)) }
        }
    }
}

/// Round badge with the athlete's initial in their theme colour.
struct ProfileAvatar: View {
    let summary: ProfileSummary
    var size: CGFloat = 36

    var body: some View {
        let theme = AppTheme(palette: ThemeCatalog.palette(id: summary.themeID))
        Text(summary.initial)
            .font(.display(size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(theme.primary, in: Circle())
            .accessibilityHidden(true)
    }
}
