import SwiftUI
import LaxPocketCore

/// One season's budget: spending against the season budget, tournament trips, by program and by category, and the expenses.
struct BudgetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    /// Nil follows the season the profile is set to.
    @State private var pickedSeason: Int?
    @State private var editing: ExpenseEditTarget?
    @State private var showBudgetEditor = false
    @State private var showAll = false
    @State private var showTripEditor = false

    var body: some View {
        let data = store.data
        let current = data.profile.currentSeason(now: store.now)
        let season = pickedSeason ?? current
        let overview = BudgetMath.season(season, in: data)
        let expenses = data.expenses(in: season).sorted { $0.date > $1.date }
        let nextShowcase = season == current ? Season.upcoming(data.events, from: store.now).first { $0.kind == .showcase } : nil
        let recent = showAll ? expenses : Array(expenses.prefix(5))

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(season: season, current: current)
                summaryCard(overview, nextShowcase: nextShowcase)

                tripsSection(season: season, data: data)

                if !overview.programs.isEmpty {
                    SectionHeader(title: "By program").padding(.top, 8)
                    Card(padding: 0) {
                        ForEach(Array(overview.programs.enumerated()), id: \.element.id) { index, line in
                            NavigationLink { ProgramBudgetView(programID: line.program?.id, season: season) } label: {
                                programRow(line).padding(.horizontal, 14)
                            }
                            .buttonStyle(.plain)
                            if index < overview.programs.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }

                if !overview.summary.byCategory.isEmpty {
                    SectionHeader(title: "By category").padding(.top, 8)
                    Card(padding: 0) {
                        ForEach(Array(overview.summary.byCategory.enumerated()), id: \.element.id) { index, row in
                            categoryRow(row, expenses: expenses).padding(.horizontal, 16)
                            if index < overview.summary.byCategory.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 16) }
                        }
                    }
                }

                SectionHeader(title: "Expenses") {
                    if expenses.count > 5 {
                        Button(showAll ? "Show less" : "See all \(expenses.count)") { showAll.toggle() }
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.top, 8)

                if expenses.isEmpty {
                    Card {
                        Text("No expenses for \(AthleteProfile.seasonLabel(start: season)) yet. Tap + to add fees, coaching, travel or gear.")
                            .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    }
                } else {
                    Card(padding: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, expense in
                            Button { editing = ExpenseEditTarget(expense: expense, season: season) } label: {
                                ExpenseListRow(expense: expense)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .contextMenu {
                                Button { editing = ExpenseEditTarget(expense: expense, season: season) } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { store.deleteExpenses([expense.id]) } label: { Label("Delete", systemImage: "trash") }
                            }
                            if index < recent.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                    Text("Tap an expense to change it or add notes.")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.caption).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { target in
            ExpenseEditorView(expense: target.expense, programID: target.programID, season: target.season, tripID: target.tripID,
                              category: target.category)
        }
        .sheet(isPresented: $showBudgetEditor) { BudgetEditorView(season: season, data: store.data) }
        .sheet(isPresented: $showTripEditor) { TripEditorView(season: season) }
    }

    // MARK: - Pieces

    private func header(season: Int, current: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                ScreenTitle(text: "Budget")
                HStack(spacing: 4) {
                    Menu {
                        Picker("Season", selection: Binding(get: { season }, set: { pickedSeason = $0 == current ? nil : $0 })) {
                            ForEach(store.data.budgetSeasons(current: current), id: \.self) { s in
                                Text(s == current ? "\(AthleteProfile.seasonLabel(start: s)) (this season)" : AthleteProfile.seasonLabel(start: s)).tag(s)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(AthleteProfile.seasonLabel(start: season)) season")
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Season: \(AthleteProfile.seasonLabel(start: season))")
                    Text("· all amounts CAD").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                }
            }
            Spacer()
            Button { editing = ExpenseEditTarget(season: season) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(theme.primary, in: Circle())
            }
            .accessibilityLabel("Add an expense")
        }
    }

    private func summaryCard(_ overview: SeasonBudgetSummary, nextShowcase: SeasonEvent?) -> some View {
        let summary = overview.summary
        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spent so far").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Formatters.money(summary.spent)).font(.display(54)).foregroundStyle(theme.primary)
                            if summary.budget > 0 {
                                Text("of \(Formatters.money(summary.budget))").font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                            }
                        }
                    }
                    Spacer()
                    Button { showBudgetEditor = true } label: {
                        Label(summary.budget > 0 ? "Edit budget" : "Set budget", systemImage: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.primary)
                }
                if summary.budget > 0 {
                    ProgressView(value: min(summary.fractionUsed, 1))
                        .tint(summary.isOverBudget ? theme.accentText : theme.primary)
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Formatters.money(abs(summary.remaining))).font(.display(24))
                            Text(summary.isOverBudget ? "Over budget" : "Remaining").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int((summary.fractionUsed * 100).rounded()))%").font(.display(24))
                            Text("Of budget used").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if overview.overall == 0 {
                        Text("No season budget set, so this is the program budgets added up.")
                            .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                    } else if overview.allocated > 0 {
                        Text("\(Formatters.money(overview.allocated)) set aside for programs\(overview.isOverAllocated ? ", more than the season budget" : "").")
                            .font(.system(size: 12, weight: overview.isOverAllocated ? .semibold : .regular))
                            .foregroundStyle(overview.isOverAllocated ? theme.accentText : AppTheme.caption)
                    }
                } else {
                    Text("No budget for this season yet. Set one for the season and for each program.")
                        .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                }
                if let showcase = nextShowcase {
                    Text("Coming up: \(showcase.title) travel & lodging")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.accentText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.accentTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Trips

    @ViewBuilder
    private func tripsSection(season: Int, data: AppData) -> some View {
        let trips = data.trips(in: season)
        SectionHeader(title: "Tournament trips") {
            Button { showTripEditor = true } label: { Label("Add trip", systemImage: "plus") }
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.top, 8)

        if trips.isEmpty {
            Card {
                Text("Going to a tournament? Add a trip to keep its fees, travel, hotel and food together, and count the days in the US.")
                    .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
            }
        } else {
            Card(padding: 0) {
                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                    NavigationLink { TripView(tripID: trip.id) } label: {
                        tripRow(TripMath.summary(trip, in: data)).padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    if index < trips.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                }
            }
            usDaysNote(season: season, data: data)
        }
    }

    private func tripRow(_ summary: TripSummary) -> some View {
        let trip = summary.trip
        return HStack(spacing: 12) {
            DateBadge(top: Formatters.monthShort(trip.departureDate), bottom: Formatters.dayNumber(trip.departureDate))
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name.isEmpty ? "Trip" : trip.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink).lineLimit(1)
                Text([trip.destination, TripDates.range(trip), summary.days == 1 ? "1 day" : "\(summary.days) days"]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(AppTheme.caption).lineLimit(1)
                if trip.isInUS {
                    Pill(text: "US · \(summary.days == 1 ? "1 day" : "\(summary.days) days")", background: theme.accentTint,
                         foreground: theme.accentText, systemImage: "airplane")
                        .padding(.top, 2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.money(summary.spent)).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(summary.isOverBudget ? theme.accentText : AppTheme.ink)
                if trip.budget > 0 {
                    Text("of \(Formatters.money(trip.budget))").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Days in the US this season, and in each calendar year the season touches, counting every trip (a day two trips
    /// share counts once).
    private func usDaysNote(season: Int, data: AppData) -> some View {
        let inSeason = TripMath.usDays(data.trips, in: TripMath.interval(season: season))
        let years = [season, season + 1].map { ($0, TripMath.usDays(data.trips, in: TripMath.interval(year: $0)).days) }
        func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(days(inSeason.days)) in the US this season\(inSeason.trips > 0 ? " (\(inSeason.trips == 1 ? "1 trip" : "\(inSeason.trips) trips"))" : "")")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.ink2)
            Text(years.map { "\(days($0.1)) in \(String($0.0))" }.joined(separator: " · ") + ", counting every trip.")
                .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func programRow(_ line: ProgramSpend) -> some View {
        HStack(spacing: 12) {
            Monogram(text: line.program?.monogram ?? "•", background: line.program == nil ? AppTheme.background : theme.primaryTint,
                     foreground: line.program == nil ? AppTheme.caption : theme.primary, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(line.program?.name ?? "Not for a program").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink).lineLimit(1)
                    Spacer()
                    Text(Formatters.money(line.spent)).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                }
                if line.budget > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppTheme.background)
                            Capsule().fill(line.isOverBudget ? theme.accentText : theme.primary)
                                .frame(width: proxy.size.width * min(line.fractionUsed, 1))
                        }
                    }
                    .frame(height: 6)
                }
                HStack {
                    Text(line.expenseCount == 1 ? "1 expense" : "\(line.expenseCount) expenses")
                    Spacer()
                    Text(line.budget > 0 ? (line.isOverBudget ? "\(Formatters.money(-line.remaining)) over \(Formatters.money(line.budget))"
                                                              : "\(Formatters.money(line.remaining)) left of \(Formatters.money(line.budget))")
                                         : (line.program == nil ? "" : "No budget"))
                        .foregroundStyle(line.isOverBudget ? theme.accentText : AppTheme.caption)
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.caption)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func categoryRow(_ row: CategorySpend, expenses: [Expense]) -> some View {
        let names = Array(Set(expenses.filter { $0.category == row.category }.map { $0.title.components(separatedBy: " · ").first ?? $0.title })).sorted()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.category.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(Formatters.money(row.amount)).font(.system(size: 15, weight: .semibold))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.background)
                    Capsule().fill(theme.primary).frame(width: proxy.size.width * row.relativeToLargest)
                }
            }
            .frame(height: 6)
            HStack {
                Text(names.prefix(3).joined(separator: " · ")).lineLimit(1)
                Spacer()
                Text("\(Int((row.share * 100).rounded()))%")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.caption)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
