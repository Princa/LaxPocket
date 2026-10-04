import SwiftUI
import LaxPocketCore

/// Sessions with the mental performance coach, and documents shared with them in Google Drive.
struct MindsetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var folder: DocFolder?
    @State private var showLink = false
    @State private var showLogSession = false

    var body: some View {
        let docs = store.data.docs.sorted { $0.updatedAt > $1.updatedAt }
        let filtered = docs.filter { folder == nil || $0.folder == folder }
        let locked = store.data.lockedDocs.filter { folder == nil || $0.folder == folder }
        let canEdit = store.data.canWrite(.mental)
        let toReview = docs.first { $0.status == .toReview }
        let coach = store.profile.mentalCoachName

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: "Mental game")
                    Text("Sessions and docs with your mental coach.").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                }

                HStack(spacing: 12) {
                    Monogram(text: "MC", background: theme.accentTint, foreground: theme.accentText, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coach.isEmpty ? "Mental performance coach" : coach).font(.system(size: 15, weight: .semibold))
                        Text("Add the coach's name in Settings").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                            .opacity(coach.isEmpty ? 1 : 0)
                    }
                    Spacer()
                    Button {
                        if let url = URL(string: "https://drive.google.com/drive/my-drive") { openURL(url) }
                    } label: {
                        Label("Drive", systemImage: "folder")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border))
                    }
                    .accessibilityLabel("Open Google Drive")
                }
                .padding(14)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let doc = toReview {
                    reviewCard(doc)
                } else if !docs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.primary)
                            .frame(width: 40, height: 40).background(theme.primaryTint, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All caught up").font(.system(size: 15, weight: .semibold))
                            Text("Nothing waiting for review").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                sessionsSection()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipButton(title: "All · \(docs.count + store.data.lockedDocs.count)", isOn: folder == nil) { folder = nil }
                        ForEach(DocFolder.allCases) { f in
                            let count = docs.filter { $0.folder == f }.count + store.data.lockedDocs.filter { $0.folder == f }.count
                            ChipButton(title: "\(f.title) · \(count)", isOn: folder == f) { folder = f }
                        }
                    }
                }
                .padding(.top, 6)

                SectionHeader(title: "Documents") {
                    Text("Tap to open · swipe for more").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                }

                if filtered.isEmpty && locked.isEmpty {
                    Card {
                        Text(canEdit ? "No documents here yet. Link one below." : "No documents here yet.")
                            .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    }
                }

                ForEach(filtered) { doc in
                    docRow(doc, canEdit: canEdit)
                }

                ForEach(locked) { doc in
                    lockedRow(doc)
                }

                if canEdit {
                    Button { showLink = true } label: {
                        Label("Link a document", systemImage: "link")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                    .padding(.top, 8)
                }

                Text("Word files open in Google Docs or the Word app, and edits save back to Drive.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.caption)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.data.canWrite(.mental) {
                    Button { showLink = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Link a document")
                }
            }
        }
        .sheet(isPresented: $showLink) { LinkDocView() }
        .sheet(isPresented: $showLogSession) { LogSessionView(category: .mental) }
    }

    /// The latest mental sessions: going over the game plan, pre-game preparation and the like.
    private func sessionsSection() -> some View {
        let sessions = store.data.sessions.filter { $0.category == .mental }.sorted { $0.date > $1.date }
        let recent = sessions.prefix(3)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sessions") {
                Text("\(Formatters.hours(Workload.hours(for: sessions).mental)) h this season")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
            }
            .padding(.top, 6)
            if recent.isEmpty {
                Card {
                    Text("Log time with your coach going over the game plan, pre-game preparation or a game review.")
                        .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Card(padding: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                        VStack(alignment: .leading, spacing: 0) {
                            SessionRow(session: session, programName: store.program(session.programID)?.name ?? "Mental session")
                            if !session.notes.isEmpty {
                                Text(session.notes)
                                    .font(.system(size: 13)).foregroundStyle(AppTheme.ink2)
                                    .lineLimit(3)
                                    .padding(.bottom, 12)
                            }
                        }
                        .padding(.horizontal, 14)
                        if index < recent.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                    }
                }
            }
            Button { showLogSession = true } label: {
                Label("Log a mental session", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    private func reviewCard(_ doc: MentalDoc) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "To review", color: theme.accentText)
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title).font(.system(size: 18, weight: .bold))
                Text(doc.note.isEmpty ? "Updated \(doc.updatedAt.formatted(.dateTime.weekday(.abbreviated).month().day())) by \(doc.updatedBy)"
                                      : "\(doc.updatedBy) updated it · \(doc.note). Read it through and reply right in the doc.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { open(doc) } label: {
                    Label("Open to edit", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                Button { store.setDocStatus(doc.id, .reviewed) } label: {
                    Text("Mark reviewed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accentText))
                }
            }
        }
        .padding(18)
        .background(theme.accentTint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func docRow(_ doc: MentalDoc, canEdit: Bool) -> some View {
        Button { open(doc) } label: {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Image(systemName: "doc.text").font(.system(size: 17))
                    Text(doc.kind.badge).font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(AppTheme.ink2)
                .frame(width: 40, height: 48)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                    Text(subtitle(for: doc))
                        .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                }
                Spacer()
                if doc.visibility != .shared {
                    Image(systemName: doc.visibility.symbol).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                        .accessibilityLabel(doc.visibility.title)
                }
                statusPill(doc.status)
                Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(AppTheme.chevron)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 70)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if store.data.access?.canLockDocs == true {
                Picker("Who sees it", selection: Binding(get: { doc.visibility }, set: { store.setDocVisibility(doc.id, $0) })) {
                    ForEach(DocVisibility.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }
            if canEdit {
                ForEach(DocStatus.allCases, id: \.self) { status in
                    Button("Mark \(status.title.lowercased())") { store.setDocStatus(doc.id, status) }
                }
                Button(role: .destructive) { store.deleteDocs([doc.id]) } label: { Label("Remove link", systemImage: "trash") }
            }
        }
        .accessibilityHint("Opens in Google Drive")
    }

    /// A doc the athlete locked: it's there, but not what it is.
    private func lockedRow(_ doc: LockedMentalDoc) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 17))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 40, height: 48)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("Locked document").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink2)
                Text("\(doc.folder.title) · \(doc.updatedAt.formatted(.dateTime.month(.abbreviated).day())) · only \(athleteName) can open it")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 70)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var athleteName: String {
        let name = store.profile.firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "the athlete" : name
    }

    private func subtitle(for doc: MentalDoc) -> String {
        var parts = [doc.folder.title, doc.updatedAt.formatted(.dateTime.month(.abbreviated).day())]
        if !doc.updatedBy.isEmpty { parts.append(doc.updatedBy) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusPill(_ status: DocStatus) -> some View {
        switch status {
        case .toReview: Pill(text: status.title, background: theme.accentTint, foreground: theme.accentText)
        case .new: Pill(text: status.title, background: theme.primary, foreground: .white)
        case .reviewed: Pill(text: status.title, background: AppTheme.background, foreground: AppTheme.muted)
        }
    }

    private func open(_ doc: MentalDoc) {
        if doc.status == .new { store.setDocStatus(doc.id, .toReview) }
        openURL(doc.url)
    }
}

struct LinkDocView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var link = ""
    @State private var folder: DocFolder = .routines
    /// New docs the athlete links start locked.
    @State private var visibility: DocVisibility = .locked

    private var url: URL? { MentalDoc.normalizedURL(from: link) }
    private var canLock: Bool { store.data.access?.canLockDocs == true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, e.g. Pre-game routine", text: $title)
                    TextField("Google Drive share link", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { link = first }
                    }
                    Picker("Folder", selection: $folder) {
                        ForEach(DocFolder.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("In Google Drive, tap ⋯ › Share › Copy link, then paste it here.")
                }
                if canLock {
                    Section {
                        Picker("Who sees it", selection: $visibility) {
                            ForEach(DocVisibility.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } footer: {
                        Text("\(visibility.detail) Anyone the file is shared with in Google Drive, like your mental coach, can still open it there.")
                    }
                }
                if let url {
                    Section("Detected") {
                        LabeledContent("Type", value: DocKind.infer(from: url).badge)
                    }
                }
            }
            .navigationTitle("Link a document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        guard let url else { return }
                        store.addDoc(MentalDoc(title: title.isEmpty ? "Untitled document" : title, url: url, folder: folder,
                                               status: .new, updatedAt: Date(), updatedBy: store.profile.firstName,
                                               visibility: canLock ? visibility : .shared))
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(url == nil)
                }
            }
        }
    }
}

extension DocVisibility {
    var symbol: String {
        switch self {
        case .shared: return "person.2"
        case .locked: return "lock.fill"
        case .hidden: return "eye.slash"
        }
    }
}
