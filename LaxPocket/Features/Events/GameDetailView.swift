import SwiftUI
import LaxPocketCore

struct GameDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    let eventID: UUID

    var body: some View {
        if let event = store.data.events.first(where: { $0.id == eventID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "\(event.team) · \(event.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                        Text(event.opponent.map { "vs \($0)" } ?? event.title)
                            .font(.display(40)).textCase(.uppercase).foregroundStyle(AppTheme.ink)
                        if !event.location.isEmpty {
                            Label("\(event.location) · \(Formatters.time(event.date))", systemImage: "mappin")
                                .font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                        }
                    }

                    scoreCard(event)

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

                    if let reflection = event.reflection {
                        SectionHeader(title: "Post-game reflection").padding(.top, 8)
                        reflectionCard(reflection)
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
        } else {
            ContentUnavailableView("Event not found", systemImage: "calendar.badge.exclamationmark")
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
