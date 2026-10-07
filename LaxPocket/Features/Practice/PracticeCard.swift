import SwiftUI
import LaxPocketCore

/// Hockey practice on the Training screen: today's shots, the streak, and the week against the shot and stickhandling
/// goals, with a shortcut to log. Tapping the card opens the practice dashboard.
struct PracticeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var showLog = false

    private let calendar = Calendar.laxWeek

    var body: some View {
        let data = store.data
        let library = data.practiceLibrary
        let sessions = data.practiceSessions
        let today = PracticeStats.days(endingOn: store.now, count: 1, sessions: sessions, library: library, calendar: calendar).first?.totals
        let week = PracticeStats.sessions(sessions, inWeekOf: store.now, calendar: calendar)
        let shots = PracticeStats.totals(week, library: library).shots
        let hands = PracticeStats.byKind(week, library: library)[.stickhandling]?.wholeMinutes ?? 0
        let streak = PracticeStats.streak(sessions, today: store.now, calendar: calendar)

        HStack(spacing: 12) {
            NavigationLink { PracticeView() } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: store.sport.practiceTitle)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text((today?.shots ?? 0).formatted()).font(.display(30)).foregroundStyle(theme.primary)
                            Text("shots today").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        }
                        Text(streak > 0 ? "\(streak)-day streak" : sessions.isEmpty ? "Goals, trends & challenges" : "Practise today to start a streak")
                            .font(.system(size: 12, weight: streak > 0 ? .semibold : .regular))
                            .foregroundStyle(streak > 0 ? theme.accentText : AppTheme.caption)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        GoalBar(value: Double(shots), goal: Double(data.profile.weeklyShotGoal), color: theme.color(for: .shooting),
                                label: "\(shots.formatted()) shots")
                        GoalBar(value: Double(hands), goal: Double(data.profile.weeklyStickhandlingGoal), color: theme.color(for: .stickhandling),
                                label: "\(hands) min hands")
                    }
                    .frame(width: 112)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the practice dashboard")

            Button { showLog = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.primary)
                    .frame(width: 44, height: 44)
                    .background(theme.primaryTint, in: Circle())
            }
            .accessibilityLabel("Log practice")
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $showLog) { LogPracticeView() }
    }
}

/// This week against a weekly goal, as a small bar with its label. With no goal, just the label.
struct GoalBar: View {
    let value: Double
    let goal: Double
    let color: Color
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(goal > 0 ? "\(label) of \(Int(goal).formatted())" : label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if goal > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.line)
                        Capsule().fill(color).frame(width: max(proxy.size.width * min(value / goal, 1), value > 0 ? 4 : 0))
                    }
                }
                .frame(height: 6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
