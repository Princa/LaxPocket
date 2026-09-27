import SwiftUI
import LaxPocketCore

/// Theme picker plus athlete profile and data controls.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmBlank = false

    var body: some View {
        let theme = AppTheme(palette: store.palette)
        NavigationStack {
            Form {
                Section {
                    ThemePreview(theme: theme, title: store.profile.seasonTitle)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Colours inspired by the top 10 D1 women's lacrosse programs (\(ThemeCatalog.source)). The app icon switches to match. No school logos or marks are used.")
                }

                Section("Theme") {
                    ForEach(ThemeCatalog.all) { palette in
                        Button { store.setTheme(palette) } label: {
                            themeRow(palette, isSelected: palette.id == store.palette.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(palette.id == store.palette.id ? .isSelected : [])
                    }
                }

                Section("Athlete") {
                    TextField("First name", text: binding(\.profile.firstName))
                        .textContentType(.givenName)
                    TextField("Class of", value: binding(\.profile.classYear), format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    TextField("Positions", text: binding(\.profile.positions))
                    Picker("NDTP standards", selection: binding(\.profile.benchmarkGroup)) {
                        ForEach(BenchmarkGroup.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Mental coach's name", text: binding(\.profile.mentalCoachName))
                }

                Section("Season") {
                    TextField("Season", text: binding(\.profile.season))
                    Stepper(value: binding(\.profile.weeklyGoalHours), in: 1...30, step: 0.5) {
                        LabeledContent("Weekly goal", value: "\(Formatters.hours(store.profile.weeklyGoalHours)) h")
                    }
                    LabeledContent("Season budget") {
                        TextField("Budget", value: binding(\.seasonBudget), format: .currency(code: "CAD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Button("Start a blank season", role: .destructive) { confirmBlank = true }
                    Button("Reload the sample season") { store.reloadSampleSeason() }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Everything is stored only on this iPhone. A blank season keeps your programs, profile and theme.")
                }
            }
            .navigationTitle("Theme & settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.bold) }
            }
            .confirmationDialog("Start a blank season?", isPresented: $confirmBlank, titleVisibility: .visible) {
                Button("Clear sessions, results, events, expenses and docs", role: .destructive) { store.startBlankSeason() }
            } message: {
                Text("Your programs, profile and theme stay.")
            }
        }
        .tint(theme.primary)
        .environment(\.appTheme, theme)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppData, Value>) -> Binding<Value> {
        Binding(
            get: { store.data[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func themeRow(_ palette: ThemePalette, isSelected: Bool) -> some View {
        let rowTheme = AppTheme(palette: palette)
        return HStack(spacing: 12) {
            Text(palette.rank.map { "\($0)" } ?? "—")
                .font(.display(16))
                .foregroundStyle(AppTheme.ink2)
                .frame(width: 32, height: 32)
                .background(AppTheme.background, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(palette.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(palette.note).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
            }
            Spacer()
            AppIconPreview(theme: rowTheme, size: 36)
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(rowTheme.primary)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 20)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Mini Home header + sample components in the chosen colours.
private struct ThemePreview: View {
    let theme: AppTheme
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Wordmark(theme: theme, size: 19)
                    Spacer()
                    Text(theme.palette.name.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.onPrimary)
                }
                Text(title).font(.display(30)).textCase(.uppercase).foregroundStyle(.white)
            }
            .padding(18)
            .background(theme.primary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("11.0").font(.display(44)).foregroundStyle(theme.primary)
                        Text("hrs").font(.display(18, weight: .semibold)).foregroundStyle(theme.primary)
                    }
                    Spacer()
                    Pill(text: "1.15 · Balanced", background: theme.primaryTint, foreground: theme.primary)
                }
                StackedHoursBar(hours: CategoryHours(team: 4.5, skills: 3.5, fitness: 3), goal: 12, height: 10)
                HStack(spacing: 16) {
                    LegendDot(color: theme.color(for: .team), label: "Team")
                    LegendDot(color: theme.color(for: .skills), label: "Skills")
                    LegendDot(color: theme.color(for: .fitness), label: "Fitness")
                }
                HStack(spacing: 6) {
                    TierBadge(tier: .elite)
                    TierBadge(tier: .competitive)
                    TierBadge(tier: .developing)
                }
            }
            .padding(18)
            .background(AppTheme.card)
        }
        .environment(\.appTheme, theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(theme.palette.name) theme")
    }
}
