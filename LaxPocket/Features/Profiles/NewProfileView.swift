import SwiftUI
import LaxPocketCore

/// Creates an athlete profile. Each profile keeps its own sessions, results, events, budget, docs and height and weight.
struct NewProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var classYear: Int?
    @State private var positions = ""
    @State private var group: BenchmarkGroup = .u15Women
    @State private var season = AthleteProfile.seasonLabel(for: Date())
    @State private var weeklyGoal = 12.0
    @State private var themeID = ThemeCatalog.defaultID
    @State private var bodyInput = BodyInput(units: .imperial)
    /// Names typed for the athlete's clubs and teams; blank ones are skipped.
    @State private var clubs: [String] = [""]

    private var trimmedName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let theme = AppTheme(palette: ThemeCatalog.palette(id: themeID))
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Class of", value: $classYear, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    TextField("Positions, e.g. Midfield / Attack", text: $positions)
                    Picker("NDTP standards", selection: $group) {
                        ForEach(BenchmarkGroup.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Athlete")
                } footer: {
                    Text("Combine results are scored against these NDTP standards.")
                }

                Section {
                    ForEach(clubs.indices, id: \.self) { index in
                        TextField(index == 0 ? "Club or team, e.g. Club 2031" : "Another team, e.g. school or box", text: $clubs[index])
                    }
                    Button { clubs.append("") } label: {
                        Label("Add another team", systemImage: "plus")
                    }
                } header: {
                    Text("Clubs & teams")
                } footer: {
                    Text("Optional. Add every team they play for. Coaches, gyms and more teams can be added later from the profile.")
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
            .navigationTitle("New athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).fontWeight(.bold).disabled(trimmedName.isEmpty || bodyInput.hasError)
                }
            }
        }
        .tint(theme.primary)
    }

    private func create() {
        let profile = AthleteProfile(firstName: trimmedName, classYear: classYear,
                                     positions: positions.trimmingCharacters(in: .whitespacesAndNewlines),
                                     benchmarkGroup: group, weeklyGoalHours: weeklyGoal,
                                     season: season.trimmingCharacters(in: .whitespacesAndNewlines), bodyUnits: bodyInput.units)
        var data = AppData.newProfile(profile, themeID: themeID)
        for club in clubs {
            let name = club.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            data.programs.append(Program(id: Program.newID(), name: name, detail: "", group: .teams, sessionCategory: .team,
                                         monogram: Program.suggestedMonogram(for: name)))
        }
        if !bodyInput.isBlank && !bodyInput.hasError {
            data.bodyMeasurements = [bodyInput.applied(to: BodyMeasurement(date: Date()))]
        }
        store.createProfile(data)
        dismiss()
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
