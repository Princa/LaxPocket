import SwiftUI
import LaxPocketCore

struct MetricsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var selectedMetric: CombineMetric?
    @State private var useNextGroup = false
    @State private var resultID: UUID?
    @State private var showAdd = false

    var body: some View {
        let results = store.data.combineResults.sorted { $0.date > $1.date }
        let result = results.first { $0.id == resultID } ?? results.first
        let baseGroup = store.profile.benchmarkGroup
        let group = useNextGroup ? (baseGroup.next ?? baseGroup) : baseGroup

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ScreenTitle(text: "Metrics")
                    Spacer()
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(theme.primary, in: Circle())
                    }
                    .accessibilityLabel("Add test results")
                }

                if let result {
                    header(result: result, all: results)
                    groupPicker(base: baseGroup)
                    content(result: result, group: group)
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No combine results yet").font(.system(size: 17, weight: .semibold))
                            Text("Add a testing day to see where each result sits against the NDTP standards for \(baseGroup.title).")
                                .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                            Button("Add results") { showAdd = true }
                                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                                .padding(.top, 6)
                        }
                    }
                }

                Text("Standards: \(NDTPStandards.source). Women's testing had no 20 m sprint in 2026.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.caption)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAdd) { AddCombineResultView() }
    }

    // MARK: - Pieces

    private func header(result: CombineResult, all: [CombineResult]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(result.event) · \(result.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                if all.count > 1 {
                    Menu {
                        ForEach(all) { item in
                            Button("\(item.event) · \(item.date.formatted(date: .abbreviated, time: .omitted))") { resultID = item.id }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle").foregroundStyle(theme.primary)
                    }
                    .accessibilityLabel("Choose testing day")
                }
                if result.isSample { Pill(text: "Sample", background: theme.accentTint, foreground: theme.accentText) }
            }
            if !bodyLine(result).isEmpty {
                Text(bodyLine(result)).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
            }
        }
    }

    private func bodyLine(_ result: CombineResult) -> String {
        var parts: [String] = []
        if !result.heightText.isEmpty { parts.append("Height \(result.heightText)") }
        if !result.weightText.isEmpty { parts.append("Weight \(result.weightText)") }
        return parts.joined(separator: " · ")
    }

    private func groupPicker(base: BenchmarkGroup) -> some View {
        Picker("Compare against", selection: $useNextGroup) {
            Text(base.title).tag(false)
            if let next = base.next { Text("\(next.title) (next)").tag(true) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Compare against")
    }

    @ViewBuilder
    private func content(result: CombineResult, group: BenchmarkGroup) -> some View {
        let scored = result.measurements.filter { NDTPStandards.thresholds(for: $0.metric, in: group) != nil }
        let counts = result.tierCounts(in: group)
        let current = scored.first { $0.metric == selectedMetric } ?? scored.first

        HStack(spacing: 10) {
            StatTile(value: "\(counts[.elite] ?? 0)", caption: "Elite", valueColor: theme.primary)
            StatTile(value: "\(counts[.competitive] ?? 0)", caption: "Competitive", valueColor: theme.primary)
            StatTile(value: "\(counts[.developing] ?? 0)", caption: "Developing", valueColor: theme.accentText)
        }

        if let current {
            DetailCard(measurement: current, group: group)
        }

        SectionHeader(title: "All results") {
            Text("Tap a test for detail").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
        }
        .padding(.top, 10)

        VStack(spacing: 8) {
            ForEach(scored, id: \.metric) { m in
                ResultRow(measurement: m, group: group, isSelected: m.metric == current?.metric) {
                    selectedMetric = m.metric
                }
            }
        }

        BalanceCard(result: result, group: group)
    }
}

private struct DetailCard: View {
    @Environment(\.appTheme) private var theme
    let measurement: CombineMeasurement
    let group: BenchmarkGroup

    var body: some View {
        let metric = measurement.metric
        let value = measurement.value
        let tier = NDTPStandards.tier(for: value, metric: metric, group: group) ?? .developing
        Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metric.title).font(.system(size: 17, weight: .bold))
                        Text(metric.quality).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        TierBadge(tier: tier, suffix: group.title)
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.format(value, withUnit: false)).font(.display(44)).foregroundStyle(theme.primary)
                        Text(metric.unit).font(.display(18, weight: .semibold)).foregroundStyle(theme.primary)
                    }
                }
                if let thresholds = NDTPStandards.thresholds(for: metric, in: group) {
                    TierBandView(metric: metric, value: value, thresholds: thresholds)
                }
                HStack(spacing: 12) {
                    ForEach(Tier.allCases, id: \.self) { t in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(theme.bandColor(t)).frame(width: 10, height: 10)
                            Text(t.title)
                        }
                    }
                    Spacer()
                    Text("Better →").fontWeight(.bold).foregroundStyle(theme.primary)
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.muted)

                if let gap = NDTPStandards.gapDescription(value, metric: metric, group: group) {
                    Text(gap).font(.system(size: 15, weight: .semibold))
                }
                if let next = group.next,
                   let nextTier = NDTPStandards.tier(for: value, metric: metric, group: next),
                   let nextGap = NDTPStandards.gapDescription(value, metric: metric, group: next) {
                    Text("At \(next.title) standard: \(nextTier.title) — \(nextGap)")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ink2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

/// Developing / Competitive / Elite band with a marker at the result. Better is always to the right.
struct TierBandView: View {
    @Environment(\.appTheme) private var theme
    let metric: CombineMetric
    let value: Double
    let thresholds: TierThresholds

    /// Scale ends in the metric's units, worse (left) to better (right), padded around the cut-offs and the result.
    private var scale: (worse: Double, better: Double) {
        let span = max(abs(thresholds.elite - thresholds.competitive), 1e-6)
        if metric.lowerIsBetter {
            return (max(thresholds.competitive, value) + span * 1.2, min(thresholds.elite, value) - span * 1.2)
        }
        return (min(thresholds.competitive, value) - span * 1.2, max(thresholds.elite, value) + span * 1.2)
    }

    private func position(_ x: Double) -> Double {
        let s = scale
        return min(max((x - s.worse) / (s.better - s.worse), 0), 1)
    }

    var body: some View {
        let compPos = position(thresholds.competitive)
        let elitePos = position(thresholds.elite)
        let marker = position(value)

        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Text(metric.format(value))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 6))
                    .fixedSize()
                    .position(x: min(max(width * marker, 40), width - 40), y: 10)

                HStack(spacing: 2) {
                    Rectangle().fill(theme.bandColor(.developing)).frame(width: max(width * compPos - 2, 0))
                    Rectangle().fill(theme.bandColor(.competitive)).frame(width: max(width * (elitePos - compPos) - 2, 0))
                    Rectangle().fill(theme.bandColor(.elite))
                }
                .frame(height: 14)
                .clipShape(Capsule())
                .offset(y: 30)

                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.ink)
                    .frame(width: 4, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white, lineWidth: 2))
                    .offset(x: width * marker - 2, y: 24)

                Text(metric.formatThreshold(thresholds.competitive))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.muted)
                    .fixedSize()
                    .position(x: width * compPos, y: 60)
                Text(metric.formatThreshold(thresholds.elite))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.muted)
                    .fixedSize()
                    .position(x: width * elitePos, y: 60)
            }
        }
        .frame(height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) \(metric.format(value)). Competitive from \(metric.formatThreshold(thresholds.competitive)), Elite from \(metric.formatThreshold(thresholds.elite)).")
    }
}

private struct ResultRow: View {
    @Environment(\.appTheme) private var theme
    let measurement: CombineMeasurement
    let group: BenchmarkGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let metric = measurement.metric
        let tier = NDTPStandards.tier(for: measurement.value, metric: metric, group: group) ?? .developing
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(metric.shortTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        Text(metric.format(measurement.value)).font(.display(18)).foregroundStyle(theme.primary)
                    }
                    Text(NDTPStandards.gapDescription(measurement.value, metric: metric, group: group) ?? "")
                        .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                TierBadge(tier: tier)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(isSelected ? theme.primaryTint : AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? theme.primary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Left vs right comparison for grip and pro agility.
private struct BalanceCard: View {
    @Environment(\.appTheme) private var theme
    let result: CombineResult
    let group: BenchmarkGroup

    var body: some View {
        let gripL = result.value(for: .gripLeft)
        let gripR = result.value(for: .gripRight)
        let agiL = result.value(for: .proAgilityLeft)
        let agiR = result.value(for: .proAgilityRight)
        if (gripL != nil && gripR != nil) || (agiL != nil && agiR != nil) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Left vs right").padding(.top, 10)
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        if let l = gripL, let r = gripR {
                            let weaker = l < r ? "Left" : "Right"
                            let diff = abs(l - r)
                            let pct = max(l, r) > 0 ? diff / max(l, r) * 100 : 0
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Grip strength").font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text(diff < 1 ? "Even" : "\(weaker) \(Int(diff)) N (\(Int(pct.rounded()))%) lower")
                                        .font(.system(size: 13, weight: .bold)).foregroundStyle(theme.accentText)
                                }
                                balanceBar("Left", l, max(l, r) * 1.1, color: l < r ? theme.accent : theme.primary, text: CombineMetric.gripLeft.format(l))
                                balanceBar("Right", r, max(l, r) * 1.1, color: r < l ? theme.accent : theme.primary, text: CombineMetric.gripRight.format(r))
                            }
                        }
                        if let l = agiL, let r = agiR {
                            let slower = l > r ? "Left" : "Right"
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Pro agility").font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text(abs(l - r) < 0.005 ? "Even" : "\(slower) \(String(format: "%.2f", abs(l - r))) s slower")
                                        .font(.system(size: 13, weight: .bold)).foregroundStyle(theme.accentText)
                                }
                                HStack(spacing: 8) {
                                    sideTile("Left", CombineMetric.proAgilityLeft.format(l), slow: l > r)
                                    sideTile("Right", CombineMetric.proAgilityRight.format(r), slow: r > l)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func balanceBar(_ label: String, _ value: Double, _ maxValue: Double, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(AppTheme.muted).frame(width: 40, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.background)
                    Capsule().fill(color).frame(width: proxy.size.width * (maxValue > 0 ? value / maxValue : 0))
                }
            }
            .frame(height: 8)
            Text(text).font(.system(size: 13, weight: .semibold)).frame(width: 56, alignment: .trailing)
        }
    }

    private func sideTile(_ label: String, _ value: String, slow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(AppTheme.muted)
            Text(value).font(.display(22)).foregroundStyle(slow ? theme.accentText : theme.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AddCombineResultView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var event = "NDTP re-test"
    @State private var date = Date()
    @State private var values: [CombineMetric: String] = [:]
    @State private var height = ""
    @State private var weight = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Testing day") {
                    TextField("Event", text: $event)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Height (e.g. 5′3″)", text: $height)
                    TextField("Weight (e.g. 103 lb)", text: $weight)
                }
                Section {
                    ForEach(CombineMetric.allCases) { metric in
                        HStack {
                            Text(metric.shortTitle)
                            Spacer()
                            TextField(metric.unit, text: binding(for: metric))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 110)
                        }
                    }
                } header: {
                    Text("Results")
                } footer: {
                    Text("Leave a test blank if it wasn't run. Grip in newtons, jumps in inches, sprints and agility in seconds.")
                }
            }
            .navigationTitle("Add results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(measurements.isEmpty)
                }
            }
        }
    }

    private var measurements: [CombineMeasurement] {
        CombineMetric.allCases.compactMap { metric in
            guard let text = values[metric], let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
            return CombineMeasurement(metric: metric, value: value)
        }
    }

    private func binding(for metric: CombineMetric) -> Binding<String> {
        Binding(get: { values[metric] ?? "" }, set: { values[metric] = $0 })
    }

    private func save() {
        store.addCombineResult(CombineResult(date: date, event: event.isEmpty ? "Testing day" : event, measurements: measurements,
                                             heightText: height, weightText: weight))
        dismiss()
    }
}
