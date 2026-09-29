import SwiftUI
import LaxPocketCore

/// Creates an athlete profile. Each profile keeps its own sessions, results, events, budget and docs.
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
    @State private var clubs: [ClubDraft] = [ClubDraft()]

    private struct ClubDraft: Identifiable {
        let id = UUID()
        var name = ""
        var detail = ""
    }

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
                    ForEach($clubs) { $club in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Club or team, e.g. Club 2031", text: $club.name)
                            TextField("Detail, e.g. Club team · U15", text: $club.detail)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { clubs.remove(atOffsets: $0) }
                    Button { clubs.append(ClubDraft()) } label: { Label("Add another club", systemImage: "plus") }
                } header: {
                    Text("Clubs & teams")
                } footer: {
                    Text("Every club or team they play for: club, league, provincial team… Team practices and games are logged against these.")
                }

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
                    Button("Create", action: create).fontWeight(.bold).disabled(trimmedName.isEmpty)
                }
            }
        }
        .tint(theme.primary)
    }

    private func create() {
        let profile = AthleteProfile(firstName: trimmedName, classYear: classYear,
                                     positions: positions.trimmingCharacters(in: .whitespacesAndNewlines),
                                     benchmarkGroup: group, weeklyGoalHours: weeklyGoal,
                                     season: season.trimmingCharacters(in: .whitespacesAndNewlines))
        store.createProfile(AppData.newProfile(profile, themeID: themeID, clubs: clubs.map { (name: $0.name, detail: $0.detail) }))
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
