import SwiftUI
import LaxPocketCore

struct EventsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var teamFilter: String?
    @State private var editing: SeasonEvent?

    var body: some View {
        let events = store.data.events
        let teams = Array(Set(events.map(\.team))).sorted()
        let filtered = events.filter { teamFilter == nil || $0.team == teamFilter }
        let record = Season.record(for: events)
        let upcoming = Season.upcoming(filtered, from: store.now)
        let results = Season.results(filtered)
        let past = Season.past(filtered, from: store.now)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        ScreenTitle(text: "Events")
                        Text("Games, tournaments & showcases").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Button { editing = EventEditorView.newEvent(team: teamFilter ?? "") } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(theme.primary, in: Circle())
                    }
                    .accessibilityLabel("Add an event")
                }

                recordCard(record)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipButton(title: "All", isOn: teamFilter == nil) { teamFilter = nil }
                        ForEach(teams, id: \.self) { team in
                            ChipButton(title: team, isOn: teamFilter == team) { teamFilter = team }
                        }
                    }
                }

                if !upcoming.isEmpty {
                    SectionHeader(title: "Upcoming").padding(.top, 8)
                    Card(padding: 0) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                            eventRow(event)
                            if index < upcoming.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }

                if !past.isEmpty {
                    SectionHeader(title: "Past") {
                        Text("Tap to add a result").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                    }
                    .padding(.top, 8)
                    Card(padding: 0) {
                        ForEach(Array(past.enumerated()), id: \.element.id) { index, event in
                            eventRow(event)
                            if index < past.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }

                if !results.isEmpty {
                    SectionHeader(title: "Results") {
                        Text("G · A · GB · DC").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                    }
                    .padding(.top, 8)
                    Card(padding: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, event in
                            NavigationLink { GameDetailView(eventID: event.id) } label: {
                                resultRow(event).padding(.horizontal, 14)
                            }
                            .buttonStyle(.plain)
                            if index < results.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }

                if upcoming.isEmpty && results.isEmpty && past.isEmpty {
                    Card {
                        Text(events.isEmpty ? "No events yet. Tap + to add a game, tournament, showcase or camp." : "No events yet for this filter.")
                            .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { event in EventEditorView(event: event) }
    }

    private func recordCard(_ record: SeasonRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Eyebrow(text: "Season record", color: theme.onPrimary)
                Spacer()
                Text("All teams · \(record.gamesPlayed) games").font(.system(size: 13)).foregroundStyle(theme.onPrimary)
            }
            HStack(alignment: .bottom, spacing: 22) {
                recordNumber(record.wins, "Wins")
                recordNumber(record.losses, "Losses")
                recordNumber(record.ties, "Ties")
            }
            if store.sport.hasGameStats {
                Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
                HStack {
                    statNumber(record.totals.goals, "Goals")
                    statNumber(record.totals.assists, "Assists")
                    statNumber(record.totals.groundBalls, "Ground balls")
                    statNumber(record.totals.drawControls, "Draw controls")
                }
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(theme.primary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func recordNumber(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.display(52))
            Text(label).font(.system(size: 12)).foregroundStyle(theme.onPrimary)
        }
    }

    private func statNumber(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.display(26))
            Text(label).font(.system(size: 11)).foregroundStyle(theme.onPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A game opens the editor to add its result. A tournament, showcase or camp opens its page, with its trip.
    @ViewBuilder
    private func eventRow(_ event: SeasonEvent) -> some View {
        if event.kind == .game {
            Button { editing = event } label: { upcomingRow(event).padding(.horizontal, 14) }
                .buttonStyle(.plain)
        } else {
            NavigationLink { GameDetailView(eventID: event.id) } label: { upcomingRow(event, showsChevron: true).padding(.horizontal, 14) }
                .buttonStyle(.plain)
        }
    }

    private func upcomingRow(_ event: SeasonEvent, showsChevron: Bool = false) -> some View {
        let isShowcase = event.kind == .showcase
        return HStack(spacing: 12) {
            DateBadge(top: Formatters.monthShort(event.date),
                      bottom: event.dateIsTentative ? "TBC" : Formatters.dayNumber(event.date),
                      background: isShowcase ? theme.accentTint : AppTheme.background,
                      foreground: isShowcase ? theme.accentText : AppTheme.ink)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.opponent.map { "\(event.team) vs \($0)" } ?? event.title)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(detail(for: event)).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                if let trip = store.data.trip(forEvent: event.id) {
                    Pill(text: "Trip · \(store.money(TripMath.summary(trip, in: store.data).spent))", background: theme.primaryTint,
                         foreground: theme.primary, systemImage: "suitcase.fill")
                        .padding(.top, 2)
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(for event: SeasonEvent) -> String {
        if event.dateIsTentative { return "\(event.location) · dates TBC" }
        var parts = [event.date.formatted(.dateTime.weekday(.abbreviated)), Formatters.time(event.date)]
        if !event.location.isEmpty { parts.append(event.location) }
        let progress = event.checklistProgress
        if progress.total > 0 { parts.append("prep \(progress.done) of \(progress.total)") }
        return parts.joined(separator: " · ")
    }

    private func resultTitle(_ event: SeasonEvent) -> String {
        let score = event.scoreLine ?? ""
        if let opponent = event.opponent { return "\(score) vs \(opponent)" }
        return "\(score) \(event.title)"
    }

    private func resultRow(_ event: SeasonEvent) -> some View {
        let outcome = event.outcome ?? .tie
        let win = outcome == .win
        return HStack(spacing: 12) {
            Text(outcome.letter)
                .font(.display(22))
                .foregroundStyle(win ? .white : theme.accentText)
                .frame(width: 44, height: 44)
                .background(win ? theme.primary : theme.accentTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(resultTitle(event))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text("\(event.team) · \(event.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                if let stats = event.stats {
                    Text(stats.summaryLine).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.ink2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(AppTheme.chevron)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
