import SwiftUI
import LaxPocketCore

/// One event: the score and stat line once there is one, the trip and what it cost, video, pre-game focus, the
/// reflection and the prep checklist.
struct GameDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var planningTrip = false
    let eventID: UUID

    var body: some View {
        if let event = store.data.events.first(where: { $0.id == eventID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: eyebrow(event))
                        Text(event.opponent.map { "vs \($0)" } ?? event.title)
                            .font(.display(40)).textCase(.uppercase).foregroundStyle(AppTheme.ink)
                        if !event.location.isEmpty {
                            Label(event.dateIsTentative ? event.location : "\(event.location) · \(Formatters.time(event.date))", systemImage: "mappin")
                                .font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                        }
                    }

                    if event.hasResult { scoreCard(event) }

                    if event.kind != .game || store.data.trip(forEvent: event.id) != nil {
                        SectionHeader(title: "Trip & costs").padding(.top, 8)
                        tripCard(event)
                    }

                    if !event.videos.isEmpty {
                        SectionHeader(title: "Video").padding(.top, 8)
                        ForEach(event.videos) { video in
                            Button { openURL(video.url) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.rectangle.fill").font(.system(size: 22)).foregroundStyle(theme.primary)
                                    Text(video.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                    Spacer()
                                    Text(video.durationText).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                                    Image(systemName: "arrow.up.right").foregroundStyle(AppTheme.chevron)
                                }
                                .padding(14)
                                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !event.focus.isEmpty {
                        SectionHeader(title: "Pre-game focus").padding(.top, 8)
                        Card(padding: 0) {
                            ForEach(Array(event.focus.enumerated()), id: \.element.id) { index, goal in
                                focusRow(goal, number: index + 1, event: event).padding(.horizontal, 14)
                                if index < event.focus.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                            }
                        }
                    }

                    let notes = store.data.coachNotes(for: event.id)
                    if !notes.isEmpty {
                        SectionHeader(title: "Coach notes").padding(.top, 8)
                        CoachNotesCard(notes: notes)
                    }

                    if let reflection = event.reflection {
                        SectionHeader(title: "Post-game reflection").padding(.top, 8)
                        reflectionCard(reflection)
                    }

                    if !event.checklist.isEmpty {
                        SectionHeader(title: "Prep checklist") {
                            Text("\(event.checklistProgress.done) of \(event.checklistProgress.total) done")
                                .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                        }
                        .padding(.top, 8)
                        checklistCard(event)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { showEdit = true } }
            }
            .sheet(isPresented: $showEdit) { EventEditorView(event: event, onDelete: { dismiss() }) }
            .sheet(isPresented: $planningTrip) { TripEditorView(event: event) }
        } else {
            ContentUnavailableView("Event not found", systemImage: "calendar.badge.exclamationmark")
        }
    }

    /// "Club 2031 · Sat, Oct 17" for a game, "Tournament · Club 2031 · Oct 16 – 18" otherwise.
    private func eyebrow(_ event: SeasonEvent) -> String {
        let parts = event.kind == .game ? [event.team, dates(event)] : [event.kind.title, event.team, dates(event)]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Sat, Oct 17", "Oct 16 – 18", or "Oct · dates TBC".
    private func dates(_ event: SeasonEvent) -> String {
        if event.dateIsTentative { return "\(event.date.formatted(.dateTime.month(.abbreviated))) · dates TBC" }
        guard let end = event.endDate, !Calendar.laxWeek.isDate(end, inSameDayAs: event.date) else {
            return event.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return TripDates.range(Trip(name: "", departureDate: event.date, returnDate: end))
    }

    /// The trip to this event and what it cost, with a way in; or a way to plan one.
    @ViewBuilder
    private func tripCard(_ event: SeasonEvent) -> some View {
        if let trip = store.data.trip(forEvent: event.id) {
            let summary = TripMath.summary(trip, in: store.data)
            Card(padding: 0) {
                NavigationLink { TripView(tripID: trip.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.name.isEmpty ? "Trip" : trip.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                Text([trip.destination, TripDates.range(trip)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(store.money(summary.spent)).font(.display(24))
                                    .foregroundStyle(summary.isOverBudget ? theme.accentText : theme.primary)
                                if trip.budget > 0 {
                                    Text("of \(store.money(trip.budget))").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                                }
                            }
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
                        }
                        HStack(spacing: 6) {
                            Pill(text: summary.days == 1 ? "1 day" : "\(summary.days) days", background: AppTheme.background, foreground: AppTheme.ink2)
                            if trip.isInUS {
                                Pill(text: "US", background: theme.accentTint, foreground: theme.accentText, systemImage: "airplane")
                            }
                            if trip.hasHotel {
                                Pill(text: trip.hotelName.isEmpty ? "Hotel" : trip.hotelName, background: AppTheme.background, foreground: AppTheme.ink2,
                                     systemImage: "bed.double.fill")
                                    .lineLimit(1)
                            }
                        }
                        if !summary.byCategory.isEmpty {
                            Text(summary.byCategory.prefix(4).map { "\($0.category.tripTitle) \(store.money($0.amount))" }.joined(separator: " · "))
                                .font(.system(size: 12)).foregroundStyle(AppTheme.caption).lineLimit(2)
                        }
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if store.data.canWrite(.budget) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Track the entry fee, travel, hotel and food for this \(event.kind.title.lowercased()) as one trip in the Budget.")
                        .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    Button { planningTrip = true } label: { Label("Plan the trip", systemImage: "suitcase.fill") }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.primary)
                }
            }
        }
    }

    private func checklistCard(_ event: SeasonEvent) -> some View {
        Card(padding: 0) {
            ForEach(Array(event.checklist.enumerated()), id: \.element.id) { index, item in
                Button { toggle(item.id, in: event) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(item.done ? theme.primary : AppTheme.chevron)
                        Text(item.title).font(.system(size: 15)).foregroundStyle(item.done ? AppTheme.caption : AppTheme.ink)
                            .strikethrough(item.done)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item.done ? .isSelected : [])
                if index < event.checklist.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
            }
        }
    }

    private func toggle(_ itemID: UUID, in event: SeasonEvent) {
        var updated = event
        if let index = updated.checklist.firstIndex(where: { $0.id == itemID }) {
            updated.checklist[index].done.toggle()
            store.saveEvent(updated)
        }
    }

    private func scoreCard(_ event: SeasonEvent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Eyebrow(text: "Final", color: theme.onPrimary)
                Spacer()
                if let outcome = event.outcome {
                    Pill(text: outcome == .win ? "WIN" : (outcome == .loss ? "LOSS" : "TIE"), background: .white, foreground: theme.primary)
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Our team").font(.system(size: 13)).foregroundStyle(theme.onPrimary)
                    Text("\(event.ourScore ?? 0)").font(.display(64))
                }
                Spacer()
                Text("–").font(.display(32, weight: .semibold)).foregroundStyle(theme.onPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(event.opponent ?? "Opponent").font(.system(size: 13)).foregroundStyle(theme.onPrimary)
                    Text("\(event.theirScore ?? 0)").font(.display(64)).foregroundStyle(theme.onPrimary)
                }
            }
            if let stats = event.stats {
                Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
                Eyebrow(text: "\(store.profile.firstName)’s line", color: theme.onPrimary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 14) {
                    stat(stats.goals, "Goals")
                    stat(stats.assists, "Assists")
                    stat(stats.shots, stats.shootingPercentage.map { "Shots · \(Int(($0 * 100).rounded()))%" } ?? "Shots")
                    stat(stats.groundBalls, "Ground balls")
                    stat(stats.drawControls, "Draw controls")
                    stat(stats.causedTurnovers, "Caused TOs")
                }
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(theme.primary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.display(30))
            Text(label).font(.system(size: 12)).foregroundStyle(theme.onPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func focusRow(_ goal: FocusGoal, number: Int, event: SeasonEvent) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.display(15))
                .frame(width: 26, height: 26)
                .background(AppTheme.background, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                if !goal.note.isEmpty { Text(goal.note).font(.system(size: 13)).foregroundStyle(AppTheme.caption) }
            }
            Spacer()
            Menu {
                ForEach(FocusOutcome.allCases, id: \.self) { outcome in
                    Button(outcome == .pending ? "Not rated" : outcome.title) { setOutcome(outcome, for: goal.id, in: event) }
                }
            } label: {
                outcomePill(goal.outcome)
            }
            .accessibilityLabel("Outcome: \(goal.outcome.title)")
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func outcomePill(_ outcome: FocusOutcome) -> some View {
        switch outcome {
        case .hit: Pill(text: "Hit", background: theme.primaryTint, foreground: theme.primary, systemImage: "checkmark")
        case .partly: Pill(text: "Partly", background: theme.accentTint, foreground: theme.accentText, systemImage: "minus")
        case .missed: Pill(text: "Missed", background: theme.accentTint, foreground: theme.accentText, systemImage: "xmark")
        case .pending: Pill(text: "Rate", background: AppTheme.background, foreground: AppTheme.muted)
        }
    }

    private func setOutcome(_ outcome: FocusOutcome, for goalID: UUID, in event: SeasonEvent) {
        var updated = event
        if let index = updated.focus.firstIndex(where: { $0.id == goalID }) {
            updated.focus[index].outcome = outcome
            store.saveEvent(updated)
        }
    }

    private func reflectionCard(_ reflection: Reflection) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                if let rating = reflection.selfRating {
                    HStack {
                        Text("Self-rating").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach(1...10, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(i <= rating ? theme.primary : AppTheme.line)
                                    .frame(width: 12, height: 18)
                            }
                        }
                        .accessibilityHidden(true)
                        Text("\(rating)/10").font(.display(22)).foregroundStyle(theme.primary)
                    }
                }
                if !reflection.wentWell.isEmpty {
                    labelled("Went well", reflection.wentWell, color: theme.primary)
                }
                if !reflection.workOn.isEmpty {
                    labelled("Work on", reflection.workOn, color: theme.accentText)
                }
                if !reflection.coachFeedback.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Coach feedback")
                        Text("“\(reflection.coachFeedback)”").font(.system(size: 15)).foregroundStyle(AppTheme.ink)
                        if let date = reflection.coachFeedbackDate {
                            Text("Added \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                                .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func labelled(_ title: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: title, color: color)
            Text(text).font(.system(size: 15)).foregroundStyle(AppTheme.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
