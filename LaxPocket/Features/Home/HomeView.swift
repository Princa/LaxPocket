import SwiftUI
import LaxPocketCore

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var showLogSession = false
    @State private var showSettings = false
    @State private var showNewProfile = false

    var body: some View {
        let data = store.data
        let now = store.now
        let weekSessions = Workload.sessions(data.sessions, inWeekOf: now)
        let weekHours = Workload.hours(for: weekSessions)
        let weeks = Workload.weeks(endingAt: now, count: 5, sessions: data.sessions)
        let ratio = Workload.acuteChronicRatio(currentWeekHours: weekHours.total, previousWeekHours: weeks.dropLast().map(\.hours.total))
        let record = Season.record(for: data.events)
        let budget = BudgetMath.summary(expenses: data.expenses, budget: data.seasonBudget)
        let upcoming = Array(Season.upcoming(data.events, from: now).prefix(4))
        let nextShowcase = Season.upcoming(data.events, from: now).first { $0.kind == .showcase }
        let docsToReview = data.docs.filter { $0.status != .reviewed }.count

        ScrollView {
            VStack(spacing: 0) {
                header(now: now)

                VStack(spacing: 12) {
                    weekCard(hours: weekHours, now: now, ratio: ratio)
                        .padding(.top, -60)

                    GettingStartedCard()

                    HStack(spacing: 10) {
                        Button { store.selectedTab = .training } label: {
                            StatTile(value: "\(Formatters.hours(Workload.hours(for: data.sessions).total)) h", caption: "Season hours")
                        }
                        Button { store.selectedTab = .events } label: {
                            StatTile(value: record.line, caption: "Game record")
                        }
                        Button { store.selectedTab = .budget } label: {
                            StatTile(value: Formatters.money(budget.spent), caption: "Spent · \(Int((budget.fractionUsed * 100).rounded()))%")
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showLogSession = true
                    } label: {
                        Label("Log a session", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: theme.primary))

                    NavigationLink { MindsetView() } label: {
                        mentalGameRow(docCount: data.docs.count, toReview: docsToReview)
                    }
                    .buttonStyle(.plain)

                    if !upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Up next") {
                                Button("All events") { store.selectedTab = .events }
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.top, 12)
                            Card(padding: 0) {
                                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                                    UpcomingRow(event: event)
                                        .padding(.horizontal, 16)
                                    if index < upcoming.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 16) }
                                }
                            }
                        }
                    }

                    if let showcase = nextShowcase {
                        ShowcaseCard(event: showcase)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(AppTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLogSession) { LogSessionView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewProfile) { NewProfileView() }
    }

    // MARK: - Pieces

    private func header(now: Date) -> some View {
        let weekNumber = seasonWeekNumber(now: now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Wordmark(theme: theme)
                Spacer()
                HStack(spacing: 8) {
                    profileMenu
                    Button {
                        showSettings = true
                    } label: {
                        headerIcon("paintpalette")
                    }
                    .accessibilityLabel("Theme and settings")
                    NavigationLink { ProgramsView() } label: {
                        headerIcon("square.grid.2x2")
                    }
                    .accessibilityLabel("Programs, teams and coaches")
                }
            }
            Eyebrow(text: "\(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · Week \(weekNumber)", color: theme.onPrimary)
                .padding(.top, 6)
            Text(store.profile.seasonTitle)
                .font(.display(40))
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(profileLine)
                .font(.system(size: 14))
                .foregroundStyle(theme.onPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 84)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            theme.primary.frame(height: 2000)
        }
    }

    private var profileMenu: some View {
        Menu {
            Section("Athletes") {
                ForEach(store.profiles) { summary in
                    Button { store.switchProfile(to: summary.id) } label: {
                        if summary.id == store.data.id {
                            Label(summary.displayName, systemImage: "checkmark")
                        } else {
                            Text(summary.displayName)
                        }
                    }
                }
            }
            Button { showNewProfile = true } label: { Label("Add athlete", systemImage: "person.badge.plus") }
        } label: {
            headerIcon(store.profiles.count > 1 ? "person.2" : "person")
        }
        .accessibilityLabel("Switch athlete")
    }

    private var profileLine: String {
        let p = store.profile
        var parts = [p.season]
        if let year = p.classYear { parts.append("Class of \(year)") }
        if !p.positions.isEmpty { parts.append(p.positions) }
        let clubs = store.data.clubs.map(\.name)
        if !clubs.isEmpty { parts.append(clubs.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.14), in: Circle())
    }

    private func seasonWeekNumber(now: Date) -> Int {
        let starts = store.data.sessions.map(\.date) + store.data.events.map(\.date)
        guard let first = starts.filter({ $0 <= now }).min() else { return 1 }
        let calendar = Calendar.laxWeek
        let a = Workload.startOfWeek(for: first, calendar: calendar)
        let b = Workload.startOfWeek(for: now, calendar: calendar)
        return (calendar.dateComponents([.weekOfYear], from: a, to: b).weekOfYear ?? 0) + 1
    }

    private func weekCard(hours: CategoryHours, now: Date, ratio: Double?) -> some View {
        let goal = store.profile.weeklyGoalHours
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Eyebrow(text: "This week")
                Spacer()
                Text(Formatters.weekRange(start: Workload.startOfWeek(for: now)))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.caption)
            }
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formatters.hours(hours.total))
                        .font(.display(60))
                        .foregroundStyle(theme.primary)
                    Text("hrs")
                        .font(.display(22, weight: .semibold))
                        .foregroundStyle(theme.primary)
                    Text("of \(Formatters.hours(goal)) h goal")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.caption)
                }
                Spacer()
                if let ratio {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Load ratio").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                        Pill(text: "\(String(format: "%.2f", ratio)) · \(Workload.zone(for: ratio).title)", background: theme.primaryTint, foreground: theme.primary)
                    }
                }
            }
            StackedHoursBar(hours: hours, goal: goal)
            HStack {
                ForEach(SessionCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 2) {
                        LegendDot(color: theme.color(for: category), label: category.title)
                        Text("\(Formatters.hours(hours[category])) h")
                            .font(.display(22, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
    }

    private func mentalGameRow(docCount: Int, toReview: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "lightbulb")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.primary)
                .frame(width: 44, height: 44)
                .background(theme.primaryTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Mental game").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(toReview > 0 ? "\(docCount) docs with your mental coach · \(toReview) to review" : "\(docCount) docs with your mental coach")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.caption)
            }
            Spacer()
            if toReview > 0 {
                Circle().fill(theme.accent).frame(width: 10, height: 10).accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").foregroundStyle(AppTheme.chevron)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct UpcomingRow: View {
    @Environment(\.appTheme) private var theme
    let event: SeasonEvent

    private var headline: String {
        if let opponent = event.opponent { return "\(event.team) vs \(opponent)" }
        return event.kind == .showcase ? event.title : "\(event.team) · \(event.title)"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(event.dateIsTentative ? Formatters.monthShort(event.date) : Formatters.weekdayShort(event.date))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.caption)
                Text(event.dateIsTentative ? "TBC" : Formatters.dayNumber(event.date))
                    .font(.display(event.dateIsTentative ? 18 : 26))
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(event.dateIsTentative ? event.location : "\(Formatters.time(event.date)) · \(event.kind.title)")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.caption)
            }
            Spacer(minLength: 8)
            Pill(text: event.kind.title, background: event.kind == .game ? AppTheme.ink : AppTheme.background,
                 foreground: event.kind == .game ? .white : AppTheme.ink2)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct ShowcaseCard: View {
    @Environment(\.appTheme) private var theme
    let event: SeasonEvent

    var body: some View {
        let progress = event.checklistProgress
        let next = event.checklist.first { !$0.done }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Showcase", color: theme.accentText)
                        Text(event.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        Text(event.location).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                    }
                    Spacer()
                    DateBadge(top: Formatters.monthShort(event.date),
                              bottom: event.dateIsTentative ? event.date.formatted(.dateTime.year()) : Formatters.dayNumber(event.date),
                              background: theme.accentTint, foreground: theme.accentText)
                }
                if progress.total > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Prep checklist").foregroundStyle(AppTheme.muted)
                            Spacer()
                            Text("\(progress.done) of \(progress.total) ready").fontWeight(.semibold)
                        }
                        .font(.system(size: 13))
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .tint(theme.accent)
                        if let next {
                            Text("Next: \(next.title.lowercased())")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.caption)
                        }
                    }
                }
            }
        }
    }
}
