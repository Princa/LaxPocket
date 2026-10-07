import SwiftUI
import LaxPocketCore

/// Who's on an athlete in the cloud, invite codes for the athlete's own login or another parent, and leaving.
struct PeopleView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let summary: ProfileSummary
    @State private var people: [ProfilePerson] = []
    @State private var invites: [InviteRow] = []
    @State private var coaches: [AthleteCoachRow] = []
    @State private var isLoading = true
    @State private var message: String?
    @State private var shownInvite: ShownInvite?
    @State private var pendingRemoval: ProfilePerson?
    @State private var confirmLeave = false

    /// An athlete that isn't in the cloud yet is uploaded with this account as its owner.
    private var access: ProfileAccess? { store.profileData(summary.id)?.access }
    private var isOwner: Bool { access?.canManagePeople ?? true }
    private var hasAthleteLogin: Bool { people.contains { $0.access.relationships.contains(.athlete) } }
    /// The athlete's other sports on this phone.
    private var otherSports: [ProfileSummary] { store.index.sportProfiles(of: summary.id).filter { $0.id != summary.id } }
    /// The owner or a parent can take the athlete off a coach's roster.
    private var isParent: Bool { access.map { $0.role == .owner || $0.relationships.contains(.parent) } ?? true }

    var body: some View {
        Form {
            Section {
                if isLoading && people.isEmpty {
                    ProgressView()
                } else if people.isEmpty {
                    Text("Only this iPhone so far. Invite someone below.").foregroundStyle(AppTheme.muted)
                }
                ForEach(people) { person in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName)
                        Text(person.access.summary).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                    }
                    .swipeActions {
                        if isOwner && !person.isMe {
                            Button("Remove", role: .destructive) { pendingRemoval = person }
                        }
                    }
                }
            } header: {
                Text("On \(summary.displayName)")
            } footer: {
                if isOwner && people.count > 1 {
                    Text(otherSports.isEmpty
                         ? "Swipe to remove someone. Their phone keeps what it already has but stops syncing."
                         : "The family is the same in every sport \(summary.displayName) plays. Swipe to remove someone: a parent or \(summary.displayName)’s own login comes off every sport. Their phone keeps what it already has but stops syncing.")
                }
            }

            if !coaches.isEmpty {
                Section {
                    ForEach(coaches) { coach in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coach.displayName)
                            Text("\(coach.kind.relationship.title) · \(coach.rosterName)").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                            if coach.kind == .mental && access?.canLockDocs == true {
                                Toggle("Can open my locked documents", isOn: Binding(get: { coach.canOpenLocked }, set: { trust(coach, $0) }))
                                    .font(.system(size: 14))
                                    .padding(.top, 4)
                            }
                        }
                        .swipeActions {
                            if isParent {
                                Button("Remove", role: .destructive) { removeCoach(coach) }
                            }
                        }
                    }
                } header: {
                    Text("Coaches")
                } footer: {
                    Text(access?.canLockDocs == true
                         ? "Coaches see training and events; mental coaches see the mental game too. A mental coach opens your locked documents only if you let them; hidden ones stay yours."
                         : "Coaches see training and events; mental coaches see the mental game too, never the budget or height and weight. Swipe to take \(summary.displayName) off a roster.")
                }
            }

            if isOwner {
                if !invites.isEmpty {
                    Section("Waiting to join") {
                        ForEach(invites) { invite in
                            Button {
                                shownInvite = ShownInvite(code: invite.code, relationship: invite.relationship)
                            } label: {
                                LabeledContent(invite.relationship.title, value: invite.displayCode)
                            }
                            .swipeActions {
                                Button("Cancel", role: .destructive) { cancel(invite) }
                            }
                        }
                    }
                }
                Section {
                    if !hasAthleteLogin {
                        Button { invite(.athlete) } label: {
                            Label("Invite \(summary.displayName)’s own login", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    Button { invite(.parent) } label: {
                        Label("Invite another parent", systemImage: "person.2.badge.plus")
                    }
                } footer: {
                    Text(hasAthleteLogin
                         ? "Another parent can see and change everything, including the budget."
                         : "With their own login, \(summary.displayName) logs training, events and health, sees the budget without changing it, and can lock mental-game documents so parents see that they’re there but not what’s in them. Inviting them is your consent for them to have an account.")
                }
            } else {
                Section {
                    Button("Leave \(summary.displayName)", role: .destructive) { confirmLeave = true }
                } footer: {
                    Text("Stops syncing \(summary.displayName)\(otherSports.isEmpty ? "" : ", in every sport,") with this account and removes them from this iPhone. The owner can invite you again.")
                }
            }

            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $shownInvite, onDismiss: { Task { await load() } }) { invite in
            InviteCodeView(athleteName: summary.displayName, invite: invite)
        }
        .confirmationDialog("Remove \(pendingRemoval?.displayName ?? "them") from \(summary.displayName)?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible, presenting: pendingRemoval) { person in
            Button("Remove", role: .destructive) { remove(person) }
        } message: { person in
            Text(person.access.relationships.contains(.athlete)
                 ? "Their login stops syncing. Documents they locked stay locked; only they can open them, if you invite them again."
                 : "They stop syncing \(summary.displayName).")
        }
        .confirmationDialog("Leave \(summary.displayName)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { leave() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            people = try await cloud.people(on: summary.id)
            invites = isOwner ? try await cloud.openInvites(for: summary.id) : []
            coaches = try await cloud.coaches(of: summary.id)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func invite(_ relationship: Relationship) {
        run {
            let code = try await cloud.invite(to: summary.id, as: relationship)
            shownInvite = ShownInvite(code: code, relationship: relationship)
        }
    }

    private func cancel(_ invite: InviteRow) {
        run {
            try await cloud.cancelInvite(invite.code)
            await load()
        }
    }

    private func remove(_ person: ProfilePerson) {
        run {
            try await cloud.remove(person.userID, from: summary.id)
            await load()
        }
    }

    private func removeCoach(_ coach: AthleteCoachRow) {
        run {
            try await cloud.removeFromRoster(coach.rosterID, athlete: summary.id)
            await load()
        }
    }

    private func trust(_ coach: AthleteCoachRow, _ trusted: Bool) {
        run {
            try await cloud.setMentalCoachTrust(athlete: summary.id, coach: coach.coachID, trusted: trusted)
            await load()
        }
    }

    private func leave() {
        run {
            try await cloud.leave(summary.id)
            dismiss()
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        message = nil
        Task {
            do {
                try await action()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct ShownInvite: Identifiable {
    var code: String
    var relationship: Relationship
    var id: String { code }
    var displayCode: String { InviteRow.displayCode(code) }
}

/// An invite code, big enough to read out, with a way to send it.
struct InviteCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    let athleteName: String
    let invite: ShownInvite

    private var instructions: String {
        "Join \(athleteName) on SportsPocket: sign in (or create an account) in Theme & settings → Cloud sync, tap Join with a code, "
            + "and enter \(invite.displayCode). The code works once and expires in a week."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(invite.relationship == .athlete ? "Code for \(athleteName)’s login" : "Code for a \(invite.relationship.title.lowercased())")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink2)
                Text(invite.displayCode)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel(invite.displayCode.map(String.init).joined(separator: " "))
                Text(instructions)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(item: instructions) {
                    Label("Send the code", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                Spacer()
            }
            .padding(24)
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Enter a code: an invite to an athlete (their own login, or another parent), or a coach's roster to add an athlete
/// on this iPhone to. Says what the code is for before using it.
struct JoinAthleteView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudStore.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var info: CodeInfo?
    @State private var athleteID: UUID?
    @State private var isWorking = false
    @State private var message: String?

    private var cleaned: String { code.uppercased().filter { $0.isLetter || $0.isNumber } }

    /// Athletes on this iPhone a parent here can add to a roster: their own, or ones not in the cloud yet.
    private var parentAthletes: [ProfileSummary] {
        store.profiles.filter { summary in
            guard !summary.isDemo, cloud.noLongerShared.contains(summary.id) == false else { return false }
            guard let access = store.profileData(summary.id)?.access else { return true }
            return access.role == .owner || access.relationships.contains(.parent)
        }
    }

    /// The sport of the roster a code is for.
    private var rosterSport: Sport? {
        if case .roster(_, _, _, let sport) = info { return sport }
        return nil
    }

    /// The parent's athletes' profiles for the roster's sport: only those can join it.
    private var rosterAthletes: [ProfileSummary] {
        parentAthletes.filter { $0.sport == rosterSport }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABCD-2345", text: $code)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: cleaned) { info = nil }
                } footer: {
                    Text("A code from a parent links your login to their athlete. A code from a coach adds your athlete to their roster.")
                }

                switch info {
                case .invite(let athlete, let relationship):
                    Section {
                        LabeledContent("Athlete", value: athlete.isEmpty ? "Unnamed" : athlete)
                        LabeledContent("You join as", value: relationship.title)
                    } footer: {
                        Text([.parent, .athlete].contains(relationship)
                             ? "\(athlete) comes onto this iPhone, with every sport they play, and syncs with your account."
                             : "\(athlete) comes onto this iPhone and syncs with your account.")
                    }
                case .roster(let name, let kind, let coach, let sport):
                    Section {
                        LabeledContent("Roster", value: name)
                        LabeledContent("Sport", value: sport.title)
                        LabeledContent("Coach", value: coach.isEmpty ? "Not named" : coach)
                        if parentAthletes.isEmpty {
                            Text("Only a parent can add an athlete to a roster, from a phone with that athlete on it.")
                                .foregroundStyle(AppTheme.muted)
                        } else if rosterAthletes.isEmpty {
                            Text("This is a \(sport.title.lowercased()) roster. Add a \(sport.title.lowercased()) profile for your athlete first, in Theme & settings → Athletes.")
                                .foregroundStyle(AppTheme.muted)
                        } else {
                            Picker("Athlete", selection: $athleteID) {
                                ForEach(rosterAthletes) { Text($0.displayName).tag(Optional($0.id)) }
                            }
                        }
                    } footer: {
                        Text("The coach sees only your athlete's \(sport.title.lowercased()) profile: \(kind.sharingSummary(for: sport)) You can take your athlete off the roster any time in People.")
                    }
                case nil:
                    EmptyView()
                }

                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Join with a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        switch info {
                        case nil:
                            Button("Next", action: describe).fontWeight(.bold).disabled(cleaned.count != 8)
                        case .invite:
                            Button("Join", action: join).fontWeight(.bold)
                        case .roster:
                            Button("Add", action: addToRoster).fontWeight(.bold).disabled(athleteID == nil)
                        }
                    }
                }
            }
        }
    }

    private func describe() {
        run {
            info = try await cloud.describe(code: cleaned)
            let choices = rosterSport == nil ? parentAthletes : rosterAthletes
            athleteID = store.hasProfile && choices.contains { $0.id == store.data.id } ? store.data.id : choices.first?.id
        }
    }

    private func join() {
        run {
            try await cloud.join(code: cleaned)
            dismiss()
        }
    }

    private func addToRoster() {
        guard let athleteID else { return }
        run {
            try await cloud.addToRoster(code: cleaned, athlete: athleteID)
            dismiss()
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        message = nil
        Task {
            do {
                try await action()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Asked once after signing in: the name others on an athlete see, and who this account is.
struct AccountSetupSection: View {
    @Environment(CloudStore.self) private var cloud
    @State private var name = ""
    @State private var kind: Relationship = .parent
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Section {
            TextField("Your name", text: $name)
                .textContentType(.name)
            Picker("I’m", selection: $kind) {
                ForEach(Relationship.allCases) { Text($0.title).tag($0) }
            }
            Button {
                isWorking = true
                message = nil
                Task {
                    do {
                        try await cloud.saveAccount(name: name, kind: kind)
                    } catch {
                        message = error.localizedDescription
                    }
                    isWorking = false
                }
            } label: {
                HStack {
                    Text("Save")
                    if isWorking { Spacer(); ProgressView() }
                }
            }
            .disabled(isWorking || name.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("About you")
        } footer: {
            Text(message ?? "Others on your athletes see this name. An athlete with their own login picks Athlete, then joins with the code a parent gives them.")
        }
    }
}
