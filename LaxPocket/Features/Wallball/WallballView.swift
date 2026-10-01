import SwiftUI
import Charts
import LaxPocketCore

/// Wall ball dashboard: today's reps and the streak, trends over time, right vs left balance, reps by drill,
/// challenge bests and the log.
struct WallballView: View {
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

    /// Which session the log sheet is for; nil for a new one.
    private struct EditTarget: Identifiable {
        let id = UUID()
        var session: WallballSession?
    }

    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var span: Span = .twoWeeks
    @State private var editing: EditTarget?
    @State private var showChallenge = false
    @State private var showAllDrills = false
    @State private var showAllHistory = false
    @State private var challengeLength: Int?

    private let calendar = Calendar.laxWeek

    var body: some View {
        let sessions = store.data.wallballSessions

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    ScreenTitle(text: "Wall ball")
                    Text("Daily reps for \(store.data.summary.displayName), right and left hand")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.muted)
                }

                actions

                if sessions.isEmpty {
                    emptyCard
                } else {
                    tiles(sessions)
                    let periods = span.isWeekly
                        ? WallballStats.weeks(endingAt: store.now, count: span.count, sessions: sessions, calendar: calendar)
                        : WallballStats.days(endingOn: store.now, count: span.count, sessions: sessions, calendar: calendar)
                    let inSpan = sessionsInSpan(sessions, periods: periods)
                    trendCard(periods)
                    balanceCard(WallballStats.reps(inSpan))
                    drillsCard(inSpan)
                    challengeCard(sessions)
                    historySection(sessions)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink { WallballDrillsView() } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Wall ball drills")
                Button { editing = EditTarget() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log wall ball reps")
            }
        }
        .sheet(item: $editing) { target in LogWallballView(session: target.session) }
        .fullScreenCover(isPresented: $showChallenge) {
            WallballChallengeView(lastChallenge: sessions.filter(\.isChallenge).max { $0.date < $1.date })
        }
    }

    // MARK: - Top

    private var actions: some View {
        HStack(spacing: 10) {
            Button { editing = EditTarget() } label: { Label("Log reps", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
            Button { showChallenge = true } label: { Label("Challenge", systemImage: "stopwatch") }
                .buttonStyle(OutlineButtonStyle(color: theme.primary))
        }
    }

    private var emptyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("No wall ball logged yet").font(.system(size: 17, weight: .semibold))
                Text("Log each day’s reps by drill and hand. The routine’s \(WallballCatalog.drills.count) drills are ready to pick: tap Pick all and choose a number for every drill, or set each one. A timed challenge counts catches against the clock and keeps your bests.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tiles(_ sessions: [WallballSession]) -> some View {
        let today = WallballStats.days(endingOn: store.now, count: 1, sessions: sessions, calendar: calendar).first?.reps.total ?? 0
        let week = WallballStats.weeks(endingAt: store.now, count: 1, sessions: sessions, calendar: calendar).first?.reps.total ?? 0
        let streak = WallballStats.streak(sessions, today: store.now, calendar: calendar)
        let best = WallballStats.bestDay(sessions, calendar: calendar)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(value: today.formatted(), caption: "Reps today", valueColor: theme.primary)
            StatTile(value: week.formatted(), caption: "Reps this week")
            StatTile(value: streak == 1 ? "1 day" : "\(streak) days", caption: streak > 0 ? "Streak" : "Streak · log today to start one")
            StatTile(value: best.map { $0.reps.total.formatted() } ?? "—",
                     caption: best.map { "Best day · \(Formatters.dayMonth($0.start))" } ?? "Best day")
        }
    }

    // MARK: - Trend

    private func sessionsInSpan(_ sessions: [WallballSession], periods: [PeriodReps]) -> [WallballSession] {
        guard let start = periods.first?.start else { return [] }
        return sessions.filter { $0.date >= start }
    }

    private func trendCard(_ periods: [PeriodReps]) -> some View {
        let total = periods.reduce(0) { $0 + $1.reps.total }
        let active = periods.filter { $0.reps.total > 0 }.count
        let unit = span.isWeekly ? "week" : "day"
        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Range", selection: $span) {
                    ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reps · last \(span.rawValue)").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        Text(total.formatted()).font(.display(44)).foregroundStyle(theme.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(active) of \(periods.count) \(unit)s").font(.system(size: 13, weight: .semibold))
                        Text("Avg \((total / max(periods.count, 1)).formatted()) a \(unit)")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.caption)
                    }
                }

                WallballTrendChart(periods: periods, weekly: span.isWeekly)
                    .frame(height: 190)

                HandLegend(reps: periods.reduce(HandReps()) { $0 + $1.reps })
            }
        }
    }

    // MARK: - Balance

    private func balanceCard(_ reps: HandReps) -> some View {
        let oneHanded = reps.right + reps.left
        let lagging = WallballStats.laggingHand(reps)
        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Right vs left").font(.system(size: 15, weight: .semibold))
                        Text("One-handed reps, last \(span.rawValue)").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                    }
                    Spacer()
                    if lagging != nil {
                        Pill(text: "Uneven", background: theme.accentTint, foreground: theme.accentText, systemImage: "exclamationmark.triangle.fill")
                    } else if oneHanded > 0 {
                        Pill(text: "Balanced", background: theme.primaryTint, foreground: theme.primary, systemImage: "checkmark")
                    }
                }

                if oneHanded == 0 {
                    Text("No right or left reps in this range.").font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                } else {
                    let left = reps.leftShare ?? 0
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Int(((1 - left) * 100).rounded()))%").font(.display(30))
                            LegendDot(color: theme.color(for: .right), label: "Right · \(reps.right.formatted())")
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Int((left * 100).rounded()))%").font(.display(30))
                            LegendDot(color: theme.color(for: .left), label: "Left · \(reps.left.formatted())")
                        }
                    }
                    SplitBar(segments: [(Double(reps.right), theme.color(for: .right)), (Double(reps.left), theme.color(for: .left))])
                        .frame(height: 12)
                        .accessibilityLabel("Right \(Int(((1 - left) * 100).rounded())) percent, left \(Int((left * 100).rounded())) percent")
                    if let lagging {
                        Text("\(lagging.title) hand is getting under \(Int(WallballStats.balanceThreshold * 100))% of the one-handed reps. Add \(lagging.title.lowercased())-hand sets to even it out: a weak hand is the first thing defenders force.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if reps.both > 0 {
                    Text("Plus \(reps.both.formatted()) reps on both-hands drills.").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                }
            }
        }
    }

    // MARK: - By drill

    private func drillsCard(_ sessions: [WallballSession]) -> some View {
        let totals = WallballStats.byDrill(sessions)
        // Most reps first; ties in routine order.
        let order = Dictionary(store.data.wallballLibrary.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = totals.sorted { ($0.value.total, order[$1.key] ?? .max) > ($1.value.total, order[$0.key] ?? .max) }
        let shown = showAllDrills ? rows : Array(rows.prefix(6))
        let most = Double(rows.first?.value.total ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By drill") {
                if rows.count > 6 {
                    Button(showAllDrills ? "Show less" : "All \(rows.count)") { showAllDrills.toggle() }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.top, 8)
            Card(padding: 0) {
                if rows.isEmpty {
                    Text("No reps in the last \(span.rawValue).").font(.system(size: 14)).foregroundStyle(AppTheme.caption).padding(14)
                }
                ForEach(Array(shown.enumerated()), id: \.element.key) { index, row in
                    let reps = row.value
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(store.data.wallballDrill(id: row.key)?.name ?? "Deleted drill").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(handText(reps)).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                            Text(reps.total.formatted()).font(.display(18)).frame(minWidth: 44, alignment: .trailing)
                        }
                        GeometryReader { proxy in
                            SplitBar(segments: WallballHand.allCases.map { (Double(reps[$0]), theme.color(for: $0)) })
                                .frame(width: max(proxy.size.width * Double(reps.total) / max(most, 1), 4))
                        }
                        .frame(height: 6)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    if index < shown.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                }
            }
        }
    }

    private func handText(_ reps: HandReps) -> String {
        reps.both > 0 && reps.right + reps.left == 0 ? "Both" : "R \(reps.right) · L \(reps.left)" + (reps.both > 0 ? " · B \(reps.both)" : "")
    }

    // MARK: - Challenges

    @ViewBuilder
    private func challengeCard(_ sessions: [WallballSession]) -> some View {
        let lengths = WallballStats.challengeLengths(sessions)
        if !lengths.isEmpty {
            let length = challengeLength.flatMap { lengths.contains($0) ? $0 : nil } ?? lengths[0]
            let bests = WallballStats.challengeBests(sessions, seconds: length)
            let drills = store.data.wallballLibrary.filter { drill in drill.hands.hands.contains { bests[DrillHand(drillID: drill.id, hand: $0)] != nil } }
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
                        Text("Most catches in \(WallballChallenge.lengthText(length))")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.caption)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }
                    ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                        HStack(spacing: 12) {
                            Text(drill.name).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            ForEach(drill.hands.hands) { hand in
                                if let best = bests[DrillHand(drillID: drill.id, hand: hand)] {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text("\(best.reps)").font(.display(20))
                                        Text(drill.hands == .each ? "\(hand.title) · \(Formatters.dayMonth(best.date))" : Formatters.dayMonth(best.date))
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.caption)
                                    }
                                    .frame(minWidth: 64, alignment: .trailing)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if index < drills.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                    }
                }
            }
        }
    }

    // MARK: - History

    private func historySection(_ sessions: [WallballSession]) -> some View {
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
                    Button { editing = EditTarget(session: session) } label: { WallballSessionRow(session: session) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteWallballSessions([session.id]) } label: { Label("Delete", systemImage: "trash") }
                        }
                    if index < shown.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                }
            }
        }
    }
}

/// One session in the log: date, total reps, and how they split.
struct WallballSessionRow: View {
    @Environment(\.appTheme) private var theme
    let session: WallballSession

    var body: some View {
        let reps = session.reps
        HStack(spacing: 12) {
            DateBadge(top: Formatters.monthShort(session.date), bottom: Formatters.dayNumber(session.date),
                      background: session.isChallenge ? theme.accentTint : AppTheme.background,
                      foreground: session.isChallenge ? theme.accentText : AppTheme.ink)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if session.isChallenge { Image(systemName: "stopwatch").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accentText) }
                    Text("\(reps.total.formatted()) reps").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                }
                Text(detail(reps)).font(.system(size: 13)).foregroundStyle(AppTheme.caption).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the session to edit")
    }

    private func detail(_ reps: HandReps) -> String {
        var parts: [String] = []
        if let seconds = session.challengeSeconds {
            parts.append("Challenge · \(session.sets.count) × \(WallballChallenge.lengthText(seconds))")
        } else {
            parts.append(session.drillCount == 1 ? "1 drill" : "\(session.drillCount) drills")
        }
        if reps.right > 0 { parts.append("R \(reps.right)") }
        if reps.left > 0 { parts.append("L \(reps.left)") }
        if reps.both > 0 { parts.append("Both \(reps.both)") }
        if let minutes = session.minutes, !session.isChallenge { parts.append("\(minutes) min") }
        if !session.notes.isEmpty { parts.append(session.notes) }
        return parts.joined(separator: " · ")
    }
}

/// Reps per day or week, stacked by hand, with the average as a dashed rule. Tap or drag to read a bar.
struct WallballTrendChart: View {
    @Environment(\.appTheme) private var theme
    let periods: [PeriodReps]
    let weekly: Bool
    @State private var selected: Date?

    /// Left at the base so the off hand's trend reads straight off the axis; both-hands drills on top.
    private static let stackOrder: [WallballHand] = [.left, .right, .both]

    private struct Point: Identifiable {
        let start: Date
        let hand: WallballHand
        let reps: Int
        var id: String { "\(start.timeIntervalSince1970)-\(hand.rawValue)" }
    }

    var body: some View {
        let points = periods.flatMap { period in
            Self.stackOrder.map { Point(start: period.start, hand: $0, reps: period.reps[$0]) }
        }
        let average = Double(periods.reduce(0) { $0 + $1.reps.total }) / Double(max(periods.count, 1))
        let unit: Calendar.Component = weekly ? .weekOfYear : .day
        let picked = selected.flatMap { date in periods.last { $0.start <= date } }

        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Date", point.start, unit: unit), y: .value("Reps", point.reps))
                    .foregroundStyle(by: .value("Hand", point.hand.title))
                    .cornerRadius(2)
                    .opacity(picked == nil || picked?.start == point.start ? 1 : 0.4)
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(AppTheme.ink2)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let picked {
                RuleMark(x: .value("Selected", picked.start, unit: unit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        readout(picked)
                    }
            }
        }
        .chartForegroundStyleScale([
            WallballHand.left.title: theme.color(for: .left),
            WallballHand.right.title: theme.color(for: .right),
            WallballHand.both.title: theme.color(for: .both)
        ])
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
        .accessibilityLabel(weekly ? "Wall ball reps per week by hand" : "Wall ball reps per day by hand")
    }

    private func readout(_ period: PeriodReps) -> some View {
        let reps = period.reps
        return VStack(alignment: .leading, spacing: 2) {
            Text(weekly ? "Week of \(Formatters.dayMonth(period.start))" : period.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.caption)
            Text("\(reps.total.formatted()) reps").font(.system(size: 13, weight: .bold)).foregroundStyle(AppTheme.ink)
            Text("R \(reps.right) · L \(reps.left)\(reps.both > 0 ? " · B \(reps.both)" : "")")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ink2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.border))
    }
}

/// Right, left and both-hands totals as a legend, so hands are never told apart by colour alone.
struct HandLegend: View {
    @Environment(\.appTheme) private var theme
    let reps: HandReps

    var body: some View {
        HStack(spacing: 14) {
            ForEach(WallballHand.allCases) { hand in
                if hand != .both || reps.both > 0 {
                    LegendDot(color: theme.color(for: hand), label: "\(hand.title) \(reps[hand].formatted())")
                }
            }
            Spacer(minLength: 0)
            Text("- - avg").font(.system(size: 12)).foregroundStyle(AppTheme.caption).accessibilityHidden(true)
        }
    }
}

/// A horizontal bar split into coloured parts, with a 2 pt gap between them.
struct SplitBar: View {
    let segments: [(Double, Color)]

    var body: some View {
        let parts = segments.filter { $0.0 > 0 }
        let total = parts.reduce(0) { $0 + $1.0 }
        GeometryReader { proxy in
            let gaps = CGFloat(max(parts.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.1)
                        .frame(width: total > 0 ? max((proxy.size.width - gaps) * part.0 / total, 2) : 0)
                }
            }
            .clipShape(Capsule())
        }
        .background(total == 0 ? AppTheme.line : .clear, in: Capsule())
        .accessibilityHidden(true)
    }
}

/// Secondary full-width button: outlined in the theme colour.
struct OutlineButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppTheme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color, lineWidth: 1.5))
    }
}
