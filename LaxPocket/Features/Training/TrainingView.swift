import SwiftUI
import Charts
import LaxPocketCore

struct TrainingView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "Week"
        case season = "Season"
        var id: String { rawValue }
    }

    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var range: Range = .week
    @State private var weekOffset = 0
    @State private var showLog = false

    private let calendar = Calendar.laxWeek

    var body: some View {
        let sessions = store.data.sessions
        let anchor = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: store.now) ?? store.now
        let weekStart = Workload.startOfWeek(for: anchor, calendar: calendar)
        let weekSessions = Workload.sessions(sessions, inWeekOf: anchor, calendar: calendar).sorted { $0.date > $1.date }
        let recent = Workload.weeks(endingAt: anchor, count: 5, sessions: sessions, calendar: calendar)
        let current = recent.last?.hours ?? CategoryHours()
        // Total hours against recent weeks for the summary; physical hours only for the workload gauge.
        let change = Workload.acuteChronicRatio(currentWeekHours: current.total, previousWeekHours: recent.dropLast().map(\.hours.total))
        let ratio = Workload.acuteChronicRatio(currentWeekHours: current.physical, previousWeekHours: recent.dropLast().map(\.hours.physical))
        let chartWeeks = Workload.weeks(endingAt: anchor, count: range == .week ? 6 : seasonWeekCount(sessions), sessions: sessions, calendar: calendar)
        let seasonHours = Workload.hours(for: sessions)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ScreenTitle(text: "Training")
                    Spacer()
                    Button { showLog = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(theme.primary, in: Circle())
                    }
                    .accessibilityLabel("Log a session")
                }

                if store.sport.hasWallball {
                    WallballCard()
                }

                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if range == .week {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("Previous week")
                        Spacer()
                        Text("\(Formatters.weekRange(start: weekStart, calendar: calendar)), \(weekStart.formatted(.dateTime.year()))")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button { weekOffset = min(weekOffset + 1, 0) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .disabled(weekOffset == 0)
                            .accessibilityLabel("Next week")
                    }
                    .foregroundStyle(AppTheme.ink)
                }

                summaryCard(hours: range == .week ? current : seasonHours,
                            sessionCount: range == .week ? weekSessions.count : sessions.count,
                            ratio: range == .week ? change : nil,
                            weeks: chartWeeks)

                if range == .week, let ratio {
                    workloadCard(ratio: ratio, current: current.physical, previous: recent.dropLast().map(\.hours.physical))
                }

                if range == .week {
                    sessionsList(weekSessions)
                } else {
                    programBreakdown()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLog) { LogSessionView() }
    }

    private func seasonWeekCount(_ sessions: [TrainingSession]) -> Int {
        guard let first = sessions.map(\.date).min() else { return 6 }
        let weeks = calendar.dateComponents([.weekOfYear], from: Workload.startOfWeek(for: first, calendar: calendar), to: Workload.startOfWeek(for: store.now, calendar: calendar)).weekOfYear ?? 0
        return min(max(weeks + 1, 6), 16)
    }

    // MARK: - Cards

    private func summaryCard(hours: CategoryHours, sessionCount: Int, ratio: Double?, weeks: [WeekTotals]) -> some View {
        Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(range == .week ? "Total this week" : "Season total")
                            .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Formatters.hours(hours.total)).font(.display(52)).foregroundStyle(theme.primary)
                            Text("hrs").font(.display(20, weight: .semibold)).foregroundStyle(theme.primary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(sessionCount) sessions").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        if let ratio {
                            let change = Int(((ratio - 1) * 100).rounded())
                            Pill(text: "\(abs(change))% vs 4-wk avg", background: theme.primaryTint, foreground: theme.primary,
                                 systemImage: change >= 0 ? "arrow.up" : "arrow.down")
                        }
                    }
                }

                HStack {
                    ForEach(SessionCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 2) {
                            LegendDot(color: theme.color(for: category), label: category.title)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(Formatters.hours(hours[category])) h").font(.display(22, weight: .semibold))
                                Text("\(Int((hours.share(of: category) * 100).rounded()))%")
                                    .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(range == .week ? "Last 6 weeks" : "Every week").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("Hours per week").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                    }
                    WeeklyHoursChart(weeks: weeks)
                        .frame(height: 170)
                }
            }
        }
    }

    private func workloadCard(ratio: Double, current: Double, previous: [Double]) -> some View {
        let zone = Workload.zone(for: ratio)
        let average = previous.isEmpty ? 0 : previous.reduce(0, +) / Double(previous.count)
        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workload").font(.system(size: 15, weight: .semibold))
                        Text("This week vs the 4 before").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                    }
                    Spacer()
                    Text(String(format: "%.2f", ratio)).font(.display(36)).foregroundStyle(theme.primary)
                }
                WorkloadGauge(ratio: ratio)
                Text("\(Formatters.hours(current)) h of physical training this week against an average of \(Formatters.hours(average)) h. \(Workload.advice(for: zone))")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sessionsList(_ sessions: [TrainingSession]) -> some View {
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        let days = byDay.keys.sorted(by: >)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sessions") {
                Text("\(sessions.count) this week").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
            }
            .padding(.top, 10)
            if sessions.isEmpty {
                Card {
                    Text("Nothing logged this week yet. Tap + to add a practice, lesson, workout or mental session.")
                        .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                }
            }
            ForEach(days, id: \.self) { day in
                Eyebrow(text: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .padding(.top, 4)
                Card(padding: 0) {
                    let items = byDay[day] ?? []
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, session in
                        SessionRow(session: session, programName: store.program(session.programID)?.name ?? "Session")
                            .padding(.horizontal, 14)
                            .contextMenu {
                                Button(role: .destructive) { store.deleteSessions([session.id]) } label: { Label("Delete", systemImage: "trash") }
                            }
                        if index < items.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                    }
                }
            }
        }
    }

    private func programBreakdown() -> some View {
        let hours = store.data.hoursByProgram
        let rows = store.data.programs.filter { (hours[$0.id] ?? 0) > 0 }.sorted { (hours[$0.id] ?? 0) > (hours[$1.id] ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By program").padding(.top, 10)
            Card(padding: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, program in
                    HStack {
                        Text(program.name).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(Formatters.hours(hours[program.id] ?? 0)) h").font(.display(18))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    if index < rows.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                }
            }
        }
    }
}

struct SessionRow: View {
    @Environment(\.appTheme) private var theme
    let session: TrainingSession
    let programName: String

    var body: some View {
        let colors = theme.tint(for: session.category)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(Formatters.hours(session.hours)).font(.display(19))
                Text("HRS").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(colors.foreground)
            .frame(width: 46, height: 46)
            .background(colors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(programName).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(detail).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
            }
            Spacer()
            Text(session.category.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.caption)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let focus = session.focus.joined(separator: ", ")
        return focus.isEmpty ? "Effort \(session.effort)" : "\(focus) · Effort \(session.effort)"
    }
}

/// Stacked weekly hours by category.
struct WeeklyHoursChart: View {
    @Environment(\.appTheme) private var theme
    let weeks: [WeekTotals]

    private struct Point: Identifiable {
        let id = UUID()
        let week: String
        let category: String
        let hours: Double
    }

    var body: some View {
        let points = weeks.flatMap { week in
            SessionCategory.allCases.map { Point(week: Formatters.dayMonth(week.weekStart), category: $0.title, hours: week.hours[$0]) }
        }
        Chart(points) { point in
            BarMark(x: .value("Week", point.week), y: .value("Hours", point.hours))
                .foregroundStyle(by: .value("Category", point.category))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale([
            SessionCategory.team.title: theme.color(for: .team),
            SessionCategory.skills.title: theme.color(for: .skills),
            SessionCategory.fitness.title: theme.color(for: .fitness),
            SessionCategory.mental.title: theme.color(for: .mental)
        ])
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(AppTheme.line)
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(AppTheme.caption)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(AppTheme.caption)
            }
        }
        .accessibilityLabel("Weekly training hours by category")
    }
}

/// Low / sweet spot / caution / high gauge with a marker.
struct WorkloadGauge: View {
    @Environment(\.appTheme) private var theme
    let ratio: Double

    private struct Zone: Identifiable {
        let label: String
        let width: Double
        let color: Color
        var id: String { label }
    }

    var body: some View {
        let range = Workload.gaugeRange
        let span = range.upperBound - range.lowerBound
        let zones: [Zone] = [
            Zone(label: "Low", width: Workload.sweetSpot.lowerBound - range.lowerBound, color: AppTheme.line),
            Zone(label: "Sweet spot", width: Workload.sweetSpot.upperBound - Workload.sweetSpot.lowerBound, color: theme.third),
            Zone(label: "Caution", width: Workload.cautionUpper - Workload.sweetSpot.upperBound, color: theme.accentSoft),
            Zone(label: "High", width: range.upperBound - Workload.cautionUpper, color: theme.accent)
        ]
        let position = (min(max(ratio, range.lowerBound), range.upperBound) - range.lowerBound) / span

        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(zones) { zone in
                            Rectangle().fill(zone.color).frame(width: max(proxy.size.width * zone.width / span - 2, 0))
                        }
                    }
                    .clipShape(Capsule())
                    .frame(height: 10)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.ink)
                        .frame(width: 4, height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white, lineWidth: 2))
                        .offset(x: proxy.size.width * position - 2)
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(zones) { zone in
                        Text(zone.label)
                            .font(.system(size: 11, weight: zone.label == "Sweet spot" ? .bold : .regular))
                            .foregroundStyle(zone.label == "Sweet spot" ? theme.primary : AppTheme.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: max(proxy.size.width * zone.width / span - 2, 0))
                    }
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load ratio \(String(format: "%.2f", ratio)), \(Workload.zone(for: ratio).title)")
    }
}
