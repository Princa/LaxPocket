import SwiftUI
import LaxPocketCore

/// Wall ball on the Training screen: today's reps, the streak and the last week, with a shortcut to log.
/// Tapping the card opens the wall ball dashboard.
struct WallballCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var showLog = false

    private let calendar = Calendar.laxWeek

    var body: some View {
        let sessions = store.data.wallballSessions
        let week = WallballStats.days(endingOn: store.now, count: 7, sessions: sessions, calendar: calendar)
        let today = week.last?.reps.total ?? 0
        let streak = WallballStats.streak(sessions, today: store.now, calendar: calendar)
        let most = Double(week.map(\.reps.total).max() ?? 0)

        HStack(spacing: 12) {
            NavigationLink { WallballView() } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Wall ball")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(today.formatted()).font(.display(30)).foregroundStyle(theme.primary)
                            Text("today").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        }
                        Text(streak > 0 ? "\(streak)-day streak" : sessions.isEmpty ? "Reports, trends & challenges" : "Log today to start a streak")
                            .font(.system(size: 12, weight: streak > 0 ? .semibold : .regular))
                            .foregroundStyle(streak > 0 ? theme.accentText : AppTheme.caption)
                    }
                    Spacer(minLength: 0)
                    // Last seven days, today on the right.
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(week) { day in
                            Capsule()
                                .fill(day.reps.total > 0 ? theme.primary : AppTheme.line)
                                .frame(width: 6, height: most > 0 ? max(4, 34 * Double(day.reps.total) / most) : 4)
                        }
                    }
                    .frame(height: 34, alignment: .bottom)
                    .accessibilityHidden(true)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the wall ball dashboard")

            Button { showLog = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.primary)
                    .frame(width: 44, height: 44)
                    .background(theme.primaryTint, in: Circle())
            }
            .accessibilityLabel("Log wall ball reps")
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $showLog) { LogWallballView() }
    }
}
