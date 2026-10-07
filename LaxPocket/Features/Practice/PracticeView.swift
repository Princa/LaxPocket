import SwiftUI
import Charts
import LaxPocketCore

/// Hockey practice dashboard: the week against the shot and stickhandling goals, today and the streak, trends over time,
/// shooting (shot mix and accuracy), stickhandling and passing by drill, challenge bests and the log.
struct PracticeView: View {
    enum Span: String, CaseIterable, Identifiable {
        case twoWeeks = "2 weeks"
        case month = "30 days"
        case season = "12 weeks"
        var id: String { rawValue }

        /// Bars on the chart: days, or weeks for the season view.
        var count: Int {
            switch self {
            case .twoWeeks: return 14
            case .month: return 30
            case .season: return 12
            }
        }

        var isWeekly: Bool { self == .season }
    }

    /// What the trend chart shows.
    enum Metric: String, CaseIterable, Identifiable {
        case shots = "Shots"
        case stickhandling = "Stickhandling"
        var id: String { rawValue }
    }

    /// Which session the log sheet is for; nil for a new one.
    private struct EditTarget: Identifiable {
        let id = UUID()
        var session: PracticeSession?
    }

    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var span: Span = .twoWeeks
    @State private var metric: Metric = .shots
    @State private var editing: EditTarget?
    @State private var showChallenge = false
    @State private var showGoals = false
    @State private var showAllHistory = false
    @State private var challengeLength: Int?

    private let calendar = Calendar.laxWeek

    var body: some View {
        let sessions = store.data.practiceSessions
        let library = store.data.practiceLibrary

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    ScreenTitle(text: store.sport.practiceTitle)
                    Text("Shots, hands and passes for \(store.data.summary.displayName)")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.muted)
                }

                actions

                if sessions.isEmpty {
                    emptyCard(library)
                } else {
                    goalsCard(sessions, library: library)
                    tiles(sessions, library: library)
                    let periods = span.isWeekly
                        ? PracticeStats.weeks(endingAt: store.now, count: span.count, sessions: sessions, library: library, calendar: calendar)
                        : PracticeStats.days(endingOn: store.now, count: span.count, sessions: sessions, library: library, calendar: calendar)
                    let inSpan = periods.first.map { start in sessions.filter { $0.date >= start.start } } ?? []
                    trendCard(sessions: inSpan, periods: periods, library: library)
                    let byDrill = PracticeStats.byDrill(inSpan, library: library)
                    ForEach(PracticeKind.allCases) { kind in
                        kindCard(kind, byDrill: byDrill, library: library)
                    }
                    challengeCard(sessions)
                    historySection(sessions, library: library)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showGoals = true } label: { Image(systemName: "target") }
                    .accessibilityLabel("Weekly goals")
                NavigationLink { PracticeDrillsView() } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Practice drills")
                Button { editing = EditTarget() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log practice")
            }
        }
        .sheet(item: $editing) { target in LogPracticeView(session: target.session) }
        .sheet(isPresented: $showGoals) { PracticeGoalsView() }
        .fullScreenCover(isPresented: $showChallenge) {
            PracticeChallengeView(lastChallenge: sessions.filter(\.isChallenge).max { $0.date < $1.date })
        }
    }

    // MARK: - Top

    private var actions: some View {
        HStack(spacing: 10) {
            Button { editing = EditTarget() } label: { Label("Log practice", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
            Button { showChallenge = true } label: { Label("Challenge", systemImage: "stopwatch") }
                .buttonStyle(OutlineButtonStyle(color: theme.primary))
        }
    }

    private func emptyCard(_ library: [PracticeDrill]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("No practice logged yet").font(.system(size: 17, weight: .semibold))
                Text("Log each day’s shots, stickhandling minutes and passes. \(library.count) drills are ready to pick, and shooting drills can count how many were on target. The week adds up against \(goalsText). A timed challenge counts touches or shots against the clock and keeps your bests.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "1,000 shots and 60 minutes of stickhandling a week", or what's left of it.
    private var goalsText: String {
        let p = store.profile
        let parts = [p.weeklyShotGoal > 0 ? "\(p.weeklyShotGoal.formatted()) shots" : nil,
                     p.weeklyStickhandlingGoal > 0 ? "\(p.weeklyStickhandlingGoal) minutes of stickhandling" : nil].compactMap { $0 }
        return parts.isEmpty ? "the week before" : parts.joined(separator: " and ") + " a week"
    }

    // MARK: - Goals

    private func goalsCard(_ sessions: [PracticeSession], library: [PracticeDrill]) -> some View {
        let week = PracticeStats.sessions(sessions, inWeekOf: store.now, calendar: calendar)
        let shots = PracticeStats.totals(week, library: library).shots
        let hands = PracticeStats.byKind(week, library: library)[.stickhandling]?.minutes ?? 0
        let p = store.profile
        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Eyebrow(text: "This week")
                    Spacer()
                    Button("Goals") { showGoals = true }.font(.system(size: 14, weight: .semibold))
                }
                goalRow(title: "Shots", value: Double(shots), goal: p.weeklyShotGoal, color: theme.color(for: .shooting),
                        format: { Int($0).formatted() })
                goalRow(title: "Stickhandling", value: hands, goal: p.weeklyStickhandlingGoal, color: theme.color(for: .stickhandling),
                        format: { "\(Int($0.rounded())) min" })
            }
        }
    }

    private func goalRow(title: String, value: Double, goal: Int, color: Color, format: (Double) -> String) -> some View {
        let pace = PracticeStats.pace(value, now: store.now, calendar: calendar)
        let done = goal > 0 && value >= Double(goal)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(format(value)).font(.display(26)).foregroundStyle(color)
                if goal > 0 {
                    Text("of \(format(Double(goal)))").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                }
            }
            if goal > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.line)
                        Capsule().fill(color).frame(width: max(proxy.size.width * min(value / Double(goal), 1), value > 0 ? 6 : 0))
                    }
                }
                .frame(height: 10)
                Text(done ? "Goal reached" : pace.map { "On pace for \(format($0)) by Sunday" } ?? "Nothing logged yet this week")
                    .font(.system(size: 13, weight: done ? .semibold : .regular))
                    .foregroundStyle(done ? theme.accentText : AppTheme.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tiles(_ sessions: [PracticeSession], library: [PracticeDrill]) -> some View {
        let today = PracticeStats.days(endingOn: store.now, count: 1, sessions: sessions, library: library, calendar: calendar).first?.totals
            ?? PracticeTotals()
        let todayHands = PracticeStats.byKind(sessions.filter { calendar.isDate($0.date, inSameDayAs: store.now) }, library: library)[.stickhandling]
        let streak = PracticeStats.streak(sessions, today: store.now, calendar: calendar)
        let best = PracticeStats.bestShotDay(sessions, library: library, calendar: calendar)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(value: today.shots.formatted(), caption: "Shots today", valueColor: theme.primary)
            StatTile(value: "\(todayHands?.wholeMinutes ?? 0) min", caption: "Stickhandling today")
            StatTile(value: streak == 1 ? "1 day" : "\(streak) days", caption: streak > 0 ? "Streak" : "Streak · practise today to start one")
            StatTile(value: best.map { $0.totals.shots.formatted() } ?? "—",
                     caption: best.map { "Most shots · \(Formatters.dayMonth($0.start))" } ?? "Most shots in a day")
        }
    }

    // MARK: - Trend

    private func trendCard(sessions: [PracticeSession], periods: [PracticePeriod], library: [PracticeDrill]) -> some View {
        let unit = span.isWeekly ? "week" : "day"
        let values: [Double]
        let hands: [Double]
        if metric == .stickhandling {
            // Stickhandling minutes per period, from that period's sessions.
            hands = periods.map { period in
                let end = calendar.date(byAdding: span.isWeekly ? .weekOfYear : .day, value: 1, to: period.start) ?? period.start
                let inPeriod = PracticeStats.sessions(sessions, from: period.start, to: end)
                return PracticeStats.byKind(inPeriod, library: library)[.stickhandling]?.minutes ?? 0
            }
            values = hands
        } else {
            hands = []
            values = periods.map { Double($0.totals.shots) }
        }
        let total = values.reduce(0, +)
        let active = values.filter { $0 > 0 }.count
        let format: (Double) -> String = metric == .shots ? { Int($0).formatted() } : { "\(Int($0.rounded())) min" }

        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Show", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Range", selection: $span) {
                    ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(metric.rawValue) · last \(span.rawValue)").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        Text(format(total)).font(.display(44)).foregroundStyle(theme.color(for: metric == .shots ? .shooting : .stickhandling))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(active) of \(periods.count) \(unit)s").font(.system(size: 13, weight: .semibold))
                        Text("Avg \(format(total / Double(max(periods.count, 1)))) a \(unit)")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.caption)
                    }
                }

                PracticeTrendChart(periods: periods, values: values,
                                   onTarget: metric == .shots ? periods.map { Double($0.totals.onTarget) } : nil,
                                   color: theme.color(for: metric == .shots ? .shooting : .stickhandling),
                                   weekly: span.isWeekly, format: format)
                    .frame(height: 190)

                if metric == .shots {
                    HStack(spacing: 14) {
                        LegendDot(color: theme.color(for: .shooting), label: "On target")
                        LegendDot(color: theme.color(for: .shooting).opacity(0.35), label: "Other shots")
                        Spacer(minLength: 0)
                        Text("- - avg").font(.system(size: 12)).foregroundStyle(AppTheme.caption).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    // MARK: - By kind

    @ViewBuilder
    private func kindCard(_ kind: PracticeKind, byDrill: [String: PracticeTotals], library: [PracticeDrill]) -> some View {
        let drills = library.filter { $0.kind == kind }
        let rows = drills.compactMap { drill in byDrill[drill.id].flatMap { $0.isEmpty ? nil : (drill, $0) } }
        if !rows.isEmpty {
            let amount: (PracticeDrill, PracticeTotals) -> Double = { drill, totals in
                switch drill.measure {
                case .shots: return Double(totals.shots)
                case .minutes: return totals.minutes
                case .reps: return Double(totals.reps)
                }
            }
            let sorted = rows.sorted { amount($0.0, $0.1) > amount($1.0, $1.1) }
            let most = sorted.first.map { amount($0.0, $0.1) } ?? 1
            let kindTotals = rows.reduce(PracticeTotals()) { $0 + $1.1 }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: kind.title) {
                    Text(PracticeSummary.line(kindTotals) ?? "").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                }
                .padding(.top, 8)
                Card(padding: 0) {
                    if kind == .shooting { shotMix(byDrill) }
                    ForEach(Array(sorted.enumerated()), id: \.element.0.id) { index, row in
                        let (drill, totals) = row
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(drill.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                if let accuracy = totals.accuracy {
                                    Text("\(Int((accuracy * 100).rounded()))% on target").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                                }
                                Text(drill.measure == .minutes ? "\(Int(totals.minutes.rounded())) min" : Int(amount(drill, totals)).formatted())
                                    .font(.display(18))
                                    .frame(minWidth: 52, alignment: .trailing)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(theme.color(for: kind))
                                    .frame(width: max(proxy.size.width * amount(drill, totals) / max(most, 1), 4))
                            }
                            .frame(height: 6)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        if index < sorted.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                    }
                }
            }
        }
    }

    /// Backhand's share of the shots, called out when it's falling behind.
    @ViewBuilder
    private func shotMix(_ byDrill: [String: PracticeTotals]) -> some View {
        if let share = PracticeStats.backhandShare(byDrill) {
            let behind = PracticeStats.backhandBehind(byDrill)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Backhand \(Int((share * 100).rounded()))% of shots").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if behind {
                        Pill(text: "Low", background: theme.accentTint, foreground: theme.accentText, systemImage: "exclamationmark.triangle.fill")
                    }
                }
                if behind {
                    Text("Under \(Int(PracticeStats.backhandThreshold * 100))% of the shots in the last \(span.rawValue). Add backhand sets: goalies read a player who only shoots one way.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            Divider().overlay(AppTheme.line).padding(.leading, 14)
        }
    }

    // MARK: - Challenges

    @ViewBuilder
    private func challengeCard(_ sessions: [PracticeSession]) -> some View {
        let lengths = PracticeStats.challengeLengths(sessions)
        if !lengths.isEmpty {
            let length = challengeLength.flatMap { lengths.contains($0) ? $0 : nil } ?? lengths[0]
            let bests = PracticeStats.challengeBests(sessions, seconds: length)
            let drills = store.data.practiceLibrary.filter { bests[$0.id] != nil }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Challenge bests") {
                    Button { showChallenge = true } label: { Label("New", systemImage: "stopwatch") }
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.top, 8)
                Card(padding: 0) {
                    if lengths.count > 1 {
                        Picker("Round length", selection: Binding(get: { length }, set: { challengeLength = $0 })) {
                            ForEach(lengths, id: \.self) { Text(WallballChallenge.lengthText($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(14)
                    } else {
                        Text("Most in \(WallballChallenge.lengthText(length))")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.caption)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }
                    ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                        if let best = bests[drill.id] {
                            HStack(spacing: 12) {
                                Text(drill.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("\(best.reps) \(drill.kind.challengeNoun)").font(.display(20))
                                    Text(Formatters.dayMonth(best.date)).font(.system(size: 11)).foregroundStyle(AppTheme.caption)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            if index < drills.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - History

    private func historySection(_ sessions: [PracticeSession], library: [PracticeDrill]) -> some View {
        let sorted = sessions.sorted { $0.date > $1.date }
        let shown = showAllHistory ? sorted : Array(sorted.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Log") {
                if sorted.count > 8 {
                    Button(showAllHistory ? "Show less" : "See all") { showAllHistory.toggle() }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.top, 8)
            Card(padding: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, session in
                    Button { editing = EditTarget(session: session) } label: { PracticeSessionRow(session: session, library: library) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .contextMenu {
                            Button(role: .destructive) { store.deletePracticeSessions([session.id]) } label: { Label("Delete", systemImage: "trash") }
                        }
                    if index < shown.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                }
            }
        }
    }
}

/// One practice session in the log: date, what was done, and notes.
struct PracticeSessionRow: View {
    @Environment(\.appTheme) private var theme
    let session: PracticeSession
    let library: [PracticeDrill]

    var body: some View {
        let byKind = PracticeStats.byKind([session], library: library)
        let totals = byKind.values.reduce(PracticeTotals()) { $0 + $1 }
        HStack(spacing: 12) {
            DateBadge(top: Formatters.monthShort(session.date), bottom: Formatters.dayNumber(session.date),
                      background: session.isChallenge ? theme.accentTint : AppTheme.background,
                      foreground: session.isChallenge ? theme.accentText : AppTheme.ink)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if session.isChallenge { Image(systemName: "stopwatch").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accentText) }
                    Text(headline(totals)).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                }
                Text(detail(totals, byKind: byKind)).font(.system(size: 13)).foregroundStyle(AppTheme.caption).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the session to edit")
    }

    private func headline(_ totals: PracticeTotals) -> String {
        if let seconds = session.challengeSeconds {
            return "Challenge · \(session.sets.count) × \(WallballChallenge.lengthText(seconds))"
        }
        if totals.shots > 0 { return "\(totals.shots.formatted()) shots" }
        if totals.minutes > 0 { return "\(max(totals.wholeMinutes, 1)) min" }
        return "\(totals.reps.formatted()) reps"
    }

    private func detail(_ totals: PracticeTotals, byKind: [PracticeKind: PracticeTotals]) -> String {
        var parts: [String] = []
        if session.isChallenge {
            parts += session.sets.map { set in
                let drill = library.first { $0.id == set.drillID }
                return "\(drill?.name ?? "Drill") \(set.amount)"
            }
        } else {
            parts.append(session.sets.count == 1 ? "1 drill" : "\(session.sets.count) drills")
            if let accuracy = totals.accuracy { parts.append("\(Int((accuracy * 100).rounded()))% on target") }
            if totals.shots > 0, let hands = byKind[.stickhandling], hands.minutes > 0 { parts.append("\(max(hands.wholeMinutes, 1)) min hands") }
            if totals.reps > 0 && (totals.shots > 0 || totals.minutes > 0) { parts.append("\(totals.reps) reps") }
            if let minutes = session.minutes { parts.append("\(minutes) min in all") }
        }
        if !session.notes.isEmpty { parts.append(session.notes) }
        return parts.joined(separator: " · ")
    }
}

/// Shots or stickhandling minutes per day or week, with the average as a dashed rule. For shots, the on-target part of
/// each bar is solid and the rest faded. Tap or drag to read a bar.
struct PracticeTrendChart: View {
    let periods: [PracticePeriod]
    let values: [Double]
    /// For shots: how many were on target in each period.
    let onTarget: [Double]?
    let color: Color
    let weekly: Bool
    let format: (Double) -> String
    @State private var selected: Date?

    private struct Point: Identifiable {
        let start: Date
        let part: String
        let value: Double
        var id: String { "\(start.timeIntervalSince1970)-\(part)" }
    }

    var body: some View {
        let points: [Point] = periods.indices.flatMap { index -> [Point] in
            let value = values[index]
            if let onTarget {
                let hit = min(onTarget[index], value)
                return [Point(start: periods[index].start, part: "On target", value: hit),
                        Point(start: periods[index].start, part: "Other", value: value - hit)]
            }
            return [Point(start: periods[index].start, part: "All", value: value)]
        }
        let average = values.reduce(0, +) / Double(max(values.count, 1))
        let unit: Calendar.Component = weekly ? .weekOfYear : .day
        let picked = selected.flatMap { date in periods.indices.last { periods[$0].start <= date } }

        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Date", point.start, unit: unit), y: .value("Amount", point.value))
                    .foregroundStyle(by: .value("Part", point.part))
                    .cornerRadius(2)
                    .opacity(picked == nil || periods[picked!].start == point.start ? 1 : 0.4)
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(AppTheme.ink2)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let picked {
                RuleMark(x: .value("Selected", periods[picked].start, unit: unit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        readout(picked)
                    }
            }
        }
        .chartForegroundStyleScale(["On target": color, "Other": color.opacity(0.35), "All": color])
        .chartLegend(.hidden)
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(AppTheme.line)
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(AppTheme.caption)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: weekly ? 4 : 5)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 11)).foregroundStyle(AppTheme.caption)
            }
        }
        .accessibilityLabel(onTarget != nil ? "Shots per \(weekly ? "week" : "day")" : "Stickhandling minutes per \(weekly ? "week" : "day")")
    }

    private func readout(_ index: Int) -> some View {
        let period = periods[index]
        return VStack(alignment: .leading, spacing: 2) {
            Text(weekly ? "Week of \(Formatters.dayMonth(period.start))" : period.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.caption)
            Text(format(values[index])).font(.system(size: 13, weight: .bold)).foregroundStyle(AppTheme.ink)
            if onTarget != nil, let accuracy = period.totals.accuracy {
                Text("\(Int((accuracy * 100).rounded()))% on target").font(.system(size: 11)).foregroundStyle(AppTheme.ink2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.border))
    }
}

/// The athlete's weekly shot and stickhandling goals.
struct PracticeGoalsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shots = AthleteProfile.defaultWeeklyShotGoal
    @State private var minutes = AthleteProfile.defaultWeeklyStickhandlingGoal
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $shots, in: 0...20_000, step: 100) {
                        LabeledContent("Shots a week", value: shots == 0 ? "No goal" : shots.formatted())
                    }
                    Stepper(value: $minutes, in: 0...1_200, step: 10) {
                        LabeledContent("Stickhandling a week", value: minutes == 0 ? "No goal" : "\(minutes) min")
                    }
                } footer: {
                    Text("Shots from every shooting drill count toward the shot goal, and minutes on stickhandling drills toward the stickhandling goal. A week runs Monday to Sunday.")
                }
                Section {
                    Button("Back to 1,000 shots and 60 minutes") {
                        shots = AthleteProfile.defaultWeeklyShotGoal
                        minutes = AthleteProfile.defaultWeeklyStickhandlingGoal
                    }
                }
            }
            .navigationTitle("Weekly goals")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                shots = store.profile.weeklyShotGoal
                minutes = store.profile.weeklyStickhandlingGoal
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setPracticeGoals(shots: shots, stickhandlingMinutes: minutes)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
