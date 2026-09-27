import SwiftUI
import LaxPocketCore

/// Documents shared with the mental performance coach, kept in Google Drive and opened by link.
struct MindsetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var folder: DocFolder?
    @State private var showLink = false

    var body: some View {
        let docs = store.data.docs.sorted { $0.updatedAt > $1.updatedAt }
        let filtered = docs.filter { folder == nil || $0.folder == folder }
        let toReview = docs.first { $0.status == .toReview }
        let coach = store.profile.mentalCoachName

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: "Mental game")
                    Text("Docs with your mental coach, linked from Google Drive.").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
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

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipButton(title: "All · \(docs.count)", isOn: folder == nil) { folder = nil }
                        ForEach(DocFolder.allCases) { f in
                            ChipButton(title: "\(f.title) · \(docs.filter { $0.folder == f }.count)", isOn: folder == f) { folder = f }
                        }
                    }
                }
                .padding(.top, 6)

                SectionHeader(title: "Documents") {
                    Text("Tap to open · swipe for more").font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                }

                if filtered.isEmpty {
                    Card { Text("No documents here yet. Link one below.").font(.system(size: 14)).foregroundStyle(AppTheme.ink2) }
                }

                ForEach(filtered) { doc in
                    docRow(doc)
                }

                Button { showLink = true } label: {
                    Label("Link a document", systemImage: "link")
                }
                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                .padding(.top, 8)

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
                Button { showLink = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Link a document")
            }
        }
        .sheet(isPresented: $showLink) { LinkDocView() }
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

    private func docRow(_ doc: MentalDoc) -> some View {
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
                statusPill(doc.status)
                Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(AppTheme.chevron)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 70)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(DocStatus.allCases, id: \.self) { status in
                Button("Mark \(status.title.lowercased())") { store.setDocStatus(doc.id, status) }
            }
            Button(role: .destructive) { store.deleteDocs([doc.id]) } label: { Label("Remove link", systemImage: "trash") }
        }
        .accessibilityHint("Opens in Google Drive")
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

    private var url: URL? { MentalDoc.normalizedURL(from: link) }

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
                                               status: .new, updatedAt: Date(), updatedBy: store.profile.firstName))
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(url == nil)
                }
            }
        }
    }
}
