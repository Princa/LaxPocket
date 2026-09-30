import SwiftUI
import Charts
import LaxPocketCore

/// Height and weight over time: the latest values, the growth rate, trend charts and the log.
struct HealthView: View {
    enum Measure: String, CaseIterable, Identifiable {
        case height = "Height"
        case weight = "Weight"
        var id: String { rawValue }
    }

    enum Span: String, CaseIterable, Identifiable {
        case threeMonths = "3M"
        case sixMonths = "6M"
        case year = "1Y"
        case all = "All"
        var id: String { rawValue }

        var months: Int? {
            switch self {
            case .threeMonths: return 3
            case .sixMonths: return 6
            case .year: return 12
            case .all: return nil
            }
        }
    }

    /// Which entry the log sheet is for; nil for a new one.
    private struct EditTarget: Identifiable {
        let id = UUID()
        var measurement: BodyMeasurement?
    }

    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var measure: Measure = .height
    @State private var span: Span = .year
    @State private var editing: EditTarget?
    @State private var showAll = false

    var body: some View {
        let entries = store.data.bodyMeasurements
        let units = store.profile.bodyUnits
        let heights = BodyTrends.heights(entries)
        let weights = BodyTrends.weights(entries)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if entries.isEmpty {
                    emptyCard
                } else {
                    HStack(spacing: 10) {
                        StatTile(value: heights.last.map { units.formatHeight($0.value) } ?? "—",
                                 caption: tileCaption("Height", heights.last), valueColor: theme.primary)
                        StatTile(value: weights.last.map { units.formatWeight($0.value) } ?? "—",
                                 caption: tileCaption("Weight", weights.last), valueColor: theme.primary)
                    }
                    growthCard(BodyTrends.growthRate(entries), heights: heights, units: units)
                    chartCard(heights: heights, weights: weights, units: units)
                    historySection(entries, units: units)
                    Button { editing = EditTarget() } label: {
                        Label("Log height & weight", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                    .padding(.top, 8)
                }

                Text("Measure without shoes, at about the same time of day: people are a little taller in the morning. Every month or two is enough to see growth.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = EditTarget() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log height and weight")
            }
        }
        .sheet(item: $editing) { target in
            LogMeasurementView(measurement: target.measurement, units: store.profile.bodyUnits)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScreenTitle(text: "Health")
            HStack {
                Text("Height and weight · \(store.data.summary.displayName)")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                Spacer()
                Picker("Units", selection: unitsBinding) {
                    ForEach(BodyUnits.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var unitsBinding: Binding<BodyUnits> {
        Binding(get: { store.profile.bodyUnits }, set: { units in store.update { $0.profile.bodyUnits = units } })
    }

    private var emptyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("No measurements yet").font(.system(size: 17, weight: .semibold))
                Text("Log \(store.data.summary.displayName)’s height and weight every month or two to chart growth and spot a growth spurt early.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Log height & weight") { editing = EditTarget() }
                    .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                    .padding(.top, 6)
            }
        }
    }

    private func tileCaption(_ label: String, _ point: BodyPoint?) -> String {
        guard let point else { return "\(label) · not logged" }
        return "\(label) · \(Formatters.dayMonth(point.date))"
    }

    private func growthCard(_ growth: GrowthRate?, heights: [BodyPoint], units: BodyUnits) -> some View {
        Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Growth rate").font(.system(size: 15, weight: .semibold))
                        Text(growthSubtitle(growth, heights: heights, units: units))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let growth {
                        Text(units.formatGrowthRate(growth.cmPerYear))
                            .font(.display(32))
                            .foregroundStyle(theme.primary)
                    }
                }
                if let growth, growth.isSpurtPace {
                    Pill(text: "Growth-spurt pace", background: theme.accentTint, foreground: theme.accentText, systemImage: "arrow.up.right")
                    Text(BodyTrends.spurtAdvice)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func growthSubtitle(_ growth: GrowthRate?, heights: [BodyPoint], units: BodyUnits) -> String {
        if let growth {
            return "\(units.formatHeightChange(growth.gainedCm)) from \(Formatters.dayMonth(growth.from)) to \(Formatters.dayMonth(growth.to))"
        }
        guard let first = heights.first else { return "Log a height to start tracking growth." }
        let ready = first.date.addingTimeInterval(Double(BodyTrends.growthWindowDays) * 86_400)
        return "Needs heights at least 3 months apart. Log one on or after \(ready.formatted(date: .abbreviated, time: .omitted))."
    }

    private func chartCard(heights: [BodyPoint], weights: [BodyPoint], units: BodyUnits) -> some View {
        let isHeight = measure == .height
        let start: Date? = span.months.flatMap { Calendar.current.date(byAdding: .month, value: -$0, to: store.now) }
        let stored = BodyTrends.points(isHeight ? heights : weights, since: start)
        let points: [BodyPoint] = stored.map { p in
            BodyPoint(id: p.id, date: p.date, value: isHeight ? units.height(fromCentimetres: p.value) : units.weight(fromKilograms: p.value))
        }
        let unit = isHeight ? units.heightUnit : units.weightUnit

        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Measure", selection: $measure) {
                    ForEach(Measure.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(measure.rawValue) · \(unit)").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(changeText(stored, isHeight: isHeight, units: units))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.caption)
                }

                if points.isEmpty {
                    Text(emptyChartText)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.caption)
                        .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    BodyTrendChart(points: points, name: measure.rawValue, start: start, end: store.now,
                                   axisLabel: { axisLabel($0, isHeight: isHeight, units: units) },
                                   valueLabel: { valueLabel($0, isHeight: isHeight, units: units) })
                        .frame(height: 190)
                }

                Picker("Range", selection: $span) {
                    ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Time range")
            }
        }
    }

    private var emptyChartText: String {
        let what = measure.rawValue.lowercased()
        return span == .all ? "No \(what) logged yet." : "No \(what) logged in this range."
    }

    /// Change across the points shown, e.g. "+0.8 in since Jun 1".
    private func changeText(_ stored: [BodyPoint], isHeight: Bool, units: BodyUnits) -> String {
        guard let change = BodyTrends.change(stored), let first = stored.first else {
            return stored.isEmpty ? "" : "Log again to see the trend"
        }
        let text = isHeight ? units.formatHeightChange(change) : units.formatWeightChange(change)
        return "\(text) since \(Formatters.dayMonth(first.date))"
    }

    /// Ticks: feet and inches for an imperial height, plain numbers otherwise (the unit is in the chart title).
    private func axisLabel(_ value: Double, isHeight: Bool, units: BodyUnits) -> String {
        if isHeight && units == .imperial { return units.formatHeight(value * BodyUnits.centimetresPerInch) }
        return BodyUnits.number(value)
    }

    private func valueLabel(_ value: Double, isHeight: Bool, units: BodyUnits) -> String {
        if isHeight { return units.formatHeight(units == .imperial ? value * BodyUnits.centimetresPerInch : value) }
        return "\(BodyUnits.number(value)) \(units.weightUnit)"
    }

    private func historySection(_ entries: [BodyMeasurement], units: BodyUnits) -> some View {
        let sorted = entries.sorted { $0.date > $1.date }
        let shown = showAll ? sorted : Array(sorted.prefix(6))
        let heightChanges = Self.changesSincePrevious(BodyTrends.heights(entries))

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Log") {
                if sorted.count > 6 {
                    Button(showAll ? "Show less" : "See all") { showAll.toggle() }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.top, 8)

            Card(padding: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    Button { editing = EditTarget(measurement: entry) } label: {
                        MeasurementRow(entry: entry, units: units, heightChange: heightChanges[entry.id])
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .contextMenu {
                        Button(role: .destructive) { store.deleteBodyMeasurements([entry.id]) } label: { Label("Delete", systemImage: "trash") }
                    }
                    if index < shown.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                }
            }
        }
    }

    /// Each point's change from the one before it, by measurement ID.
    private static func changesSincePrevious(_ points: [BodyPoint]) -> [UUID: Double] {
        var changes: [UUID: Double] = [:]
        for index in points.indices.dropFirst() {
            changes[points[index].id] = points[index].value - points[index - 1].value
        }
        return changes
    }
}

/// One line in the log: date, height and weight, and how much taller since the previous height.
private struct MeasurementRow: View {
    let entry: BodyMeasurement
    let units: BodyUnits
    /// Centimetres since the previous height, if there was one.
    let heightChange: Double?

    var body: some View {
        HStack(spacing: 12) {
            DateBadge(top: Formatters.monthShort(entry.date), bottom: Formatters.dayNumber(entry.date))
            VStack(alignment: .leading, spacing: 3) {
                Text(values).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 13)).foregroundStyle(AppTheme.caption).lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the entry to edit")
    }

    private var values: String {
        var parts: [String] = []
        if let cm = entry.heightCm { parts.append(units.formatHeight(cm)) }
        if let kg = entry.weightKg { parts.append(units.formatWeight(kg)) }
        return parts.joined(separator: " · ")
    }

    private var detail: String {
        var parts: [String] = []
        if let heightChange { parts.append("\(units.formatHeightChange(heightChange)) since last height") }
        if !entry.note.isEmpty { parts.append(entry.note) }
        return parts.joined(separator: " · ")
    }
}

/// One measure over time: a 2 pt line through ringed points, with the latest value labelled.
struct BodyTrendChart: View {
    @Environment(\.appTheme) private var theme
    /// Values in the athlete's units, oldest first.
    let points: [BodyPoint]
    let name: String
    /// Left end of the time axis; the first point when nil.
    var start: Date?
    /// Right end of the time axis, unless a point is later.
    var end: Date
    let axisLabel: (Double) -> String
    let valueLabel: (Double) -> String

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(theme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(points.dropLast()) { point in
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .symbol { dot }
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(valueLabel(point.value))
            }
            // The latest value is the one labelled on the chart.
            if let last = points.last {
                PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                    .symbol { dot }
                    .accessibilityLabel(last.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(valueLabel(last.value))
                    .annotation(position: .top, alignment: .trailing, spacing: 6) {
                        Text(valueLabel(last.value))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.ink2)
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(AppTheme.line)
                AxisValueLabel {
                    Text(axisLabel(value.as(Double.self) ?? 0)).font(.system(size: 11)).foregroundStyle(AppTheme.caption)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(AppTheme.line)
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(AppTheme.caption)
            }
        }
        .accessibilityLabel("\(name) over time")
    }

    /// An 8 pt dot in a 2 pt ring of the card colour, so it stays crisp where it sits on the line.
    private var dot: some View {
        Circle()
            .fill(theme.primary)
            .padding(2)
            .background(AppTheme.card, in: Circle())
            .frame(width: 12, height: 12)
    }

    private var xDomain: ClosedRange<Date> {
        let first = start ?? points.first?.date ?? end
        let last = max(end, points.last?.date ?? end)
        guard first < last else { return first.addingTimeInterval(-15 * 86_400)...last.addingTimeInterval(15 * 86_400) }
        return first...last
    }

    /// Padded around the data rather than starting at zero, so a growth of an inch or two is visible.
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.2, 1)
        return (low - pad)...(high + pad)
    }
}
