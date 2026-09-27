import SwiftUI
import LaxPocketCore

/// White rounded card used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Big condensed uppercase screen title.
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.display(40))
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Section header, e.g. "UP NEXT" with an optional trailing link or note.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.display(22))
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Small eyebrow label ("THIS WEEK").
struct Eyebrow: View {
    let text: String
    var color: Color = AppTheme.muted
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Rounded pill label.
struct Pill: View {
    let text: String
    var background: Color
    var foreground: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 12, weight: .bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }
}

struct TierBadge: View {
    @Environment(\.appTheme) private var theme
    let tier: Tier
    var suffix: String? = nil

    var body: some View {
        let colors = theme.tierColors(tier)
        Pill(text: suffix.map { "\(tier.title) · \($0)" } ?? tier.title, background: colors.background, foreground: colors.foreground)
    }
}

/// Coloured dot + label, used in legends and category chips.
struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
        .font(.system(size: 13))
        .foregroundStyle(AppTheme.muted)
    }
}

/// Big number + caption tile.
struct StatTile: View {
    let value: String
    let caption: String
    var valueColor: Color = AppTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.display(28))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal stacked bar showing hours per category plus the remaining gap to the goal.
struct StackedHoursBar: View {
    @Environment(\.appTheme) private var theme
    let hours: CategoryHours
    var goal: Double? = nil
    var height: CGFloat = 12

    var body: some View {
        let remainder = max((goal ?? 0) - hours.total, 0)
        let segments: [(Double, Color)] = [
            (hours.team, theme.color(for: .team)),
            (hours.skills, theme.color(for: .skills)),
            (hours.fitness, theme.color(for: .fitness)),
            (remainder, AppTheme.line)
        ].filter { $0.0 > 0 }
        let total = segments.reduce(0) { $0 + $1.0 }

        GeometryReader { proxy in
            let gaps = CGFloat(max(segments.count - 1, 0)) * 3
            HStack(spacing: 3) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.1)
                        .frame(width: total > 0 ? max((proxy.size.width - gaps) * segment.0 / total, 2) : 0)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .background(total == 0 ? AppTheme.line : Color.clear, in: Capsule())
        .accessibilityHidden(true)
    }
}

/// Month + day badge used in schedule lists.
struct DateBadge: View {
    let top: String
    let bottom: String
    var background: Color = AppTheme.background
    var foreground: Color = AppTheme.ink

    var body: some View {
        VStack(spacing: 0) {
            Text(top)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(foreground == AppTheme.ink ? AppTheme.caption : foreground)
            Text(bottom)
                .font(.display(22))
                .foregroundStyle(foreground)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: 48, height: 48)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Program monogram square.
struct Monogram: View {
    let text: String
    var background: Color
    var foreground: Color
    var size: CGFloat = 40

    var body: some View {
        Text(text)
            .font(.display(16))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Chip-style toggle button used for filters and tags.
struct ChipButton: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let isOn: Bool
    var style: Style = .solid
    let action: () -> Void

    enum Style { case solid, accent }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(Capsule().stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var foreground: Color {
        guard isOn else { return AppTheme.ink2 }
        return style == .solid ? .white : theme.accentText
    }

    private var background: Color {
        guard isOn else { return AppTheme.card }
        return style == .solid ? theme.primary : theme.accentTint
    }

    private var border: Color {
        guard isOn else { return AppTheme.border }
        return style == .solid ? theme.primary : theme.accent
    }
}

/// Primary full-width button.
struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(color.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Simple wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Sample-data notice with a way out.
struct SampleBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme

    var body: some View {
        if store.data.isSample {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(theme.accentText)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You're looking at a sample season.")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Explore, then start fresh from Settings to log your own.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(theme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

enum Formatters {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CAD"
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        return f
    }()

    static func money(_ value: Double) -> String {
        currency.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    static func hours(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func weekdayShort(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    static func monthShort(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    static func dayNumber(_ date: Date) -> String {
        date.formatted(.dateTime.day())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func weekRange(start: Date, calendar: Calendar = .laxWeek) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(dayMonth(start)) – \(end.formatted(.dateTime.day()))"
    }
}
