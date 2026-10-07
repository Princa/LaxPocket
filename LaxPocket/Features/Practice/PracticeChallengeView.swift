import SwiftUI
import LaxPocketCore

/// A timed practice challenge: pick drills and a time, and each drill gets that time on the clock. After each round the
/// athlete enters what they counted (touches, shots, passes) or taps them in as they go, and the results are saved as a
/// session. Built like the wall ball challenge, without hands.
struct PracticeChallengeView: View {
    private enum Phase: Equatable {
        case setup
        case getReady(round: Int, until: Date)
        case running(round: Int, until: Date)
        case paused(round: Int, remaining: TimeInterval)
        case entry(round: Int)
        case summary
    }

    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .setup
    @State private var picked: Set<String>
    @State private var seconds: Int
    /// Drill IDs, one round each.
    @State private var rounds: [String] = []
    /// The count for each round; nil until entered, or when skipped.
    @State private var results: [Int?] = []
    @State private var tapCount = 0
    @State private var startedAt = Date()
    @State private var notes = ""
    @State private var confirmEnd = false
    @State private var confirmDiscard = false

    init(lastChallenge: PracticeSession? = nil) {
        // A first challenge starts with quick hands: touches in 30 seconds.
        _picked = State(initialValue: Set(lastChallenge?.sets.map(\.drillID) ?? ["quick-hands"]))
        _seconds = State(initialValue: lastChallenge?.challengeSeconds ?? PracticeChallenge.defaultLength)
    }

    private var drills: [PracticeDrill] { store.data.practiceLibrary.filter { !$0.isHidden } }
    private var bests: [String: ChallengeBest] { PracticeStats.challengeBests(store.data.practiceSessions, seconds: seconds) }

    private var isTimed: Bool {
        switch phase {
        case .getReady, .running, .paused: return true
        case .setup, .entry, .summary: return false
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .setup:
                setup
            case .getReady(let round, let until):
                getReady(round, until: until)
            case .running(let round, let until):
                running(round, until: until, paused: nil)
            case .paused(let round, let remaining):
                running(round, until: nil, paused: remaining)
            case .entry(let round):
                entry(round)
            case .summary:
                summary
            }
        }
        // The timed screens are dark; everything else matches the rest of the app.
        .preferredColorScheme(isTimed ? .dark : .light)
        .task(id: phase) { await advance() }
        .confirmationDialog("End the challenge?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("See results so far") {
                // A round waiting for its count keeps what's shown; one still on the clock doesn't count.
                if case .entry(let round) = phase { results[round] = results[round] ?? tapCount }
                phase = .summary
            }
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func drill(_ id: String) -> PracticeDrill? { store.data.practiceDrill(id: id) }
    private func name(_ id: String) -> String { drill(id)?.name ?? "Drill" }
    private func noun(_ id: String) -> String { drill(id)?.kind.challengeNoun ?? "reps" }

    // MARK: - Setup

    private var setup: some View {
        let planned = drills.filter { picked.contains($0.id) }.map(\.id)
        let bests = self.bests
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Time per drill", color: AppTheme.caption)
                        HStack(spacing: 6) {
                            ForEach(PracticeChallenge.lengths, id: \.self) { length in
                                Button(shortLength(length)) { seconds = length }
                                    .buttonStyle(QuickButtonStyle(color: theme.primary, filled: seconds == length, expands: true))
                                    .accessibilityLabel(WallballChallenge.lengthText(length))
                                    .accessibilityAddTraits(seconds == length ? .isSelected : [])
                            }
                        }
                    }

                    ForEach(PracticeKind.allCases) { kind in
                        let inKind = drills.filter { $0.kind == kind }
                        if !inKind.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "\(kind.title) · counts \(kind.challengeNoun)", color: theme.color(for: kind))
                                Card(padding: 0, radius: 14) {
                                    ForEach(Array(inKind.enumerated()), id: \.element.id) { index, drill in
                                        drillRow(drill, best: bests[drill.id])
                                        if index < inKind.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 52) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Text(planned.isEmpty ? "Pick the drills to time" : planText(planned.count))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                    Button { start(planned) } label: { Label("Start challenge", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                        .disabled(planned.isEmpty)
                        .opacity(planned.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle("Timed challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func drillRow(_ drill: PracticeDrill, best: ChallengeBest?) -> some View {
        let isOn = picked.contains(drill.id)
        return Button {
            if isOn { picked.remove(drill.id) } else { picked.insert(drill.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isOn ? theme.color(for: drill.kind) : AppTheme.border)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(drill.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                    Text(best.map { "Best in \(shortLength(seconds)): \($0.reps) \(drill.kind.challengeNoun)" } ?? drill.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.caption)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func planText(_ count: Int) -> String {
        let total = count * (seconds + PracticeChallenge.getReadySeconds)
        let minutes = max(1, Int((Double(total) / 60).rounded()))
        return "\(count) round\(count == 1 ? "" : "s") of \(WallballChallenge.lengthText(seconds)) · about \(minutes) min"
    }

    /// "30s", "90s", "2 min".
    private func shortLength(_ seconds: Int) -> String {
        seconds >= 120 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds)s"
    }

    // MARK: - Rounds

    // Only the clock sits in a TimelineView: redrawing buttons ten times a second swallows taps.

    private func getReady(_ round: Int, until: Date) -> some View {
        VStack(spacing: 18) {
            roundHeader(round)
            Spacer()
            Text("Up next").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.onPrimary)
            drillTitle(round)
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let left = max(0, Int(ceil(until.timeIntervalSince(context.date))))
                Text(left == 0 ? "Go!" : "\(left)")
                    .font(.display(140))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .accessibilityLabel(left == 0 ? "Go" : "Starting in \(left)")
            }
            Spacer()
            Button("Skip countdown") { phase = .running(round: round, until: Date().addingTimeInterval(TimeInterval(seconds))) }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minHeight: 44)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.primary)
    }

    private func running(_ round: Int, until: Date?, paused: TimeInterval?) -> some View {
        VStack(spacing: 16) {
            roundHeader(round)
            drillTitle(round)
                .padding(.top, 8)

            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let remaining = paused ?? max(0, (until ?? context.date).timeIntervalSince(context.date))
                let progress = 1 - remaining / Double(seconds)
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(clock(remaining))
                            .font(.display(72))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        if paused != nil {
                            Text("Paused").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.onPrimary)
                        } else if let best = bests[rounds[round]] {
                            Text("Best \(best.reps)").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.onPrimary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .frame(width: 220, height: 220)

            Button {
                tapCount += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                VStack(spacing: 4) {
                    Text("\(tapCount)").font(.display(56)).monospacedDigit()
                    Text("Tap to count \(noun(rounds[round])) (optional)").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(theme.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(paused != nil)
            .opacity(paused != nil ? 0.6 : 1)
            .accessibilityLabel("Count one")
            .accessibilityValue("\(tapCount)")

            HStack(spacing: 12) {
                Button {
                    if let paused {
                        phase = .running(round: round, until: Date().addingTimeInterval(paused))
                    } else if let until {
                        phase = .paused(round: round, remaining: max(0, until.timeIntervalSinceNow))
                    }
                } label: {
                    Label(paused == nil ? "Pause" : "Resume", systemImage: paused == nil ? "pause.fill" : "play.fill")
                }
                .buttonStyle(OnPrimaryButtonStyle())
                Button { finishRound(round) } label: { Label("Done", systemImage: "checkmark") }
                    .buttonStyle(OnPrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.primary)
    }

    private func roundHeader(_ round: Int) -> some View {
        HStack {
            Text("Round \(round + 1) of \(rounds.count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.onPrimary)
            Spacer()
            Button { confirmEnd = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("End challenge")
        }
    }

    private func drillTitle(_ round: Int) -> some View {
        let id = rounds[round]
        return VStack(spacing: 8) {
            Text(name(id))
                .font(.display(40))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text("COUNT \(noun(id).uppercased())")
                .font(.system(size: 14, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.white, in: Capsule())
        }
    }

    // MARK: - Entry

    private func entry(_ round: Int) -> some View {
        let id = rounds[round]
        let value = results[round] ?? tapCount
        let best = bests[id]
        let isBest = value > 0 && value > (best?.reps ?? 0)
        let isLast = round == rounds.count - 1
        return NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(name(id)).font(.display(30))
                    Text(WallballChallenge.lengthText(seconds)).font(.system(size: 15)).foregroundStyle(AppTheme.muted)
                }
                .padding(.top, 12)

                Text("How many \(noun(id))?").font(.system(size: 17, weight: .semibold))

                HStack(spacing: 10) {
                    adjust(-5, round: round, value: value)
                    adjust(-1, round: round, value: value)
                    Text("\(value)")
                        .font(.display(84))
                        .monospacedDigit()
                        .foregroundStyle(theme.primary)
                        .frame(minWidth: 120)
                        .accessibilityLabel("\(value) \(noun(id))")
                    adjust(1, round: round, value: value)
                    adjust(5, round: round, value: value)
                }

                Group {
                    if isBest {
                        Pill(text: best == nil ? "First score at this length" : "New best · was \(best!.reps)",
                             background: theme.accentTint, foreground: theme.accentText, systemImage: "trophy.fill")
                    } else if let best {
                        Text("Best: \(best.reps) on \(Formatters.dayMonth(best.date))").font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                    }
                }
                .frame(minHeight: 26)

                Spacer()

                VStack(spacing: 10) {
                    Button(isLast ? "Finish" : "Next: \(name(rounds[round + 1]))") {
                        results[round] = value
                        next(after: round)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: theme.primary))

                    HStack(spacing: 10) {
                        Button("Redo round") {
                            results[round] = nil
                            tapCount = 0
                            phase = .getReady(round: round, until: Date().addingTimeInterval(TimeInterval(PracticeChallenge.getReadySeconds)))
                        }
                        .buttonStyle(QuickButtonStyle(color: theme.primary, filled: false, expands: true))
                        Button("Skip") {
                            results[round] = nil
                            next(after: round)
                        }
                        .buttonStyle(QuickButtonStyle(color: theme.primary, filled: false, expands: true))
                    }
                }
            }
            .padding(16)
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle("Round \(round + 1) of \(rounds.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("End") { confirmEnd = true } }
            }
        }
    }

    private func adjust(_ delta: Int, round: Int, value: Int) -> some View {
        Button {
            results[round] = min(max(value + delta, 0), PracticeSet.amountRange.upperBound)
        } label: {
            Text(delta > 0 ? "+\(delta)" : "−\(abs(delta))")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 48, height: 48)
                .background(AppTheme.card, in: Circle())
                .overlay(Circle().stroke(AppTheme.border))
        }
        .buttonStyle(.plain)
        .disabled(delta < 0 && value == 0)
        .accessibilityLabel(delta > 0 ? "\(delta) more" : "\(abs(delta)) fewer")
    }

    // MARK: - Summary

    private var summary: some View {
        let bests = self.bests
        let done = rounds.indices.compactMap { index in results[index].map { (index, rounds[index], $0) } }.filter { $0.2 > 0 }
        let newBests = done.filter { $0.2 > (bests[$0.1]?.reps ?? 0) }.count
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card(padding: 20, radius: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Challenge").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                            Text("\(done.count) of \(rounds.count) round\(rounds.count == 1 ? "" : "s") · \(WallballChallenge.lengthText(seconds)) each")
                                .font(.display(24))
                                .foregroundStyle(theme.primary)
                            if newBests > 0 {
                                Pill(text: newBests == 1 ? "1 new best" : "\(newBests) new bests", background: theme.accentTint,
                                     foreground: theme.accentText, systemImage: "trophy.fill")
                                    .padding(.top, 4)
                            }
                        }
                    }

                    Card(padding: 0) {
                        ForEach(Array(rounds.enumerated()), id: \.offset) { index, id in
                            let count = results[index] ?? 0
                            let isBest = count > 0 && count > (bests[id]?.reps ?? 0)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name(id)).font(.system(size: 15, weight: .semibold))
                                    Text(noun(id).capitalized).font(.system(size: 13))
                                        .foregroundStyle(drill(id).map { theme.color(for: $0.kind) } ?? AppTheme.caption)
                                }
                                Spacer()
                                if isBest { Image(systemName: "trophy.fill").foregroundStyle(theme.accentText).accessibilityLabel("New best") }
                                Text(results[index] == nil ? "Skipped" : "\(count)")
                                    .font(results[index] == nil ? .system(size: 14) : .display(22))
                                    .foregroundStyle(results[index] == nil ? AppTheme.caption : AppTheme.ink)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            if index < rounds.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }

                    TextField("Notes: how it felt, what slipped", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.border))
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                Button("Save challenge") { save() }
                    .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                    .disabled(done.isEmpty)
                    .opacity(done.isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Discard") { confirmDiscard = true } }
            }
            .confirmationDialog("Discard these results?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
        }
    }

    // MARK: - Flow

    private func start(_ planned: [String]) {
        rounds = planned
        results = Array(repeating: nil, count: planned.count)
        startedAt = Date()
        tapCount = 0
        phase = .getReady(round: 0, until: Date().addingTimeInterval(TimeInterval(PracticeChallenge.getReadySeconds)))
    }

    private func finishRound(_ round: Int) {
        ChallengeFeedback.roundOver()
        phase = .entry(round: round)
    }

    private func next(after round: Int) {
        guard round + 1 < rounds.count else {
            phase = .summary
            return
        }
        tapCount = 0
        phase = .getReady(round: round + 1, until: Date().addingTimeInterval(TimeInterval(PracticeChallenge.getReadySeconds)))
    }

    /// Runs the clock for the current phase. A new phase cancels it.
    private func advance() async {
        switch phase {
        case .getReady(let round, let until):
            while until.timeIntervalSinceNow > 0.05 {
                ChallengeFeedback.tick()
                guard await sleep(min(1, until.timeIntervalSinceNow)) else { return }
            }
            ChallengeFeedback.go()
            phase = .running(round: round, until: Date().addingTimeInterval(TimeInterval(seconds)))
        case .running(let round, let until):
            // Ticks for the last three seconds.
            guard await sleep(until.timeIntervalSinceNow - 3) else { return }
            while until.timeIntervalSinceNow > 0.05 {
                ChallengeFeedback.tick()
                guard await sleep(min(1, until.timeIntervalSinceNow)) else { return }
            }
            finishRound(round)
        case .setup, .paused, .entry, .summary:
            return
        }
    }

    /// Waits, or returns false if the phase changed meanwhile.
    private func sleep(_ seconds: TimeInterval) async -> Bool {
        guard seconds > 0 else { return !Task.isCancelled }
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    private func save() {
        let sets = rounds.indices.compactMap { index in results[index].map { PracticeSet(drillID: rounds[index], amount: $0) } }
        let normalized = PracticeSession.normalized(sets)
        guard !normalized.isEmpty else { return }
        let minutes = max(1, Int(ceil(Double(normalized.count * seconds) / 60)))
        store.savePracticeSession(PracticeSession(date: startedAt, sets: normalized, minutes: minutes, challengeSeconds: seconds,
                                                  notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)))
        dismiss()
    }

    private func clock(_ remaining: TimeInterval) -> String {
        let whole = Int(ceil(remaining))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
