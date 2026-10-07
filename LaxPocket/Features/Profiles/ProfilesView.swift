import SwiftUI
import LaxPocketCore

/// Lists the athletes on this iPhone and each one's sports: switch, add or remove.
struct ProfilesView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudStore.self) private var cloud
    @State private var showNew = false
    @State private var addingSportTo: AppData?
    @State private var pendingDelete: ProfileSummary?

    var body: some View {
        let athletes = store.index.athletes
        List {
            ForEach(Array(athletes.enumerated()), id: \.element.first?.athleteKey) { position, sports in
                Section {
                    ForEach(sports) { summary in
                        Button { store.switchProfile(to: summary.id) } label: { row(summary) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) { pendingDelete = summary }
                            }
                            .accessibilityAddTraits(summary.id == store.data.id ? .isSelected : [])
                    }
                    if let first = sports.first, !store.sportsToAdd(for: first.id).isEmpty {
                        Button {
                            addingSportTo = store.profileData(first.id)
                        } label: {
                            Label("Add a sport for \(first.displayName)", systemImage: "plus")
                        }
                    }
                } header: {
                    Text(sports.first?.displayName ?? "")
                } footer: {
                    if position == athletes.count - 1 {
                        Text("Each sport has its own sessions, results, events, budget, documents and height and weight log, kept apart from the athlete's other sports. Tap to switch; swipe to delete.")
                    }
                }
            }

            Section {
                Button { showNew = true } label: { Label("Add athlete", systemImage: "person.badge.plus") }
            }
        }
        .navigationTitle("Athletes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNew) { NewProfileView() }
        .sheet(item: $addingSportTo) { athlete in NewProfileView(athlete: athlete) }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDelete) { summary in
            Button("Delete \(store.listName(summary))", role: .destructive) { store.deleteProfile(summary.id) }
        } message: { summary in
            Text(cloud.isSignedIn
                 ? "Removes \(store.listName(summary)) from this iPhone. The copy in your cloud account stays; delete it from Cloud sync if you want it gone everywhere."
                 : "Removes \(store.listName(summary))’s profile, sessions, results, events, expenses, linked docs and height and weight log from this iPhone. This can’t be undone.")
        }
    }

    private var deleteTitle: String {
        "Delete \(pendingDelete.map(store.listName) ?? "this athlete")?"
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func row(_ summary: ProfileSummary) -> some View {
        let isActive = summary.id == store.data.id
        return HStack(spacing: 12) {
            ProfileAvatar(summary: summary)
            VStack(alignment: .leading, spacing: 2) {
                Label(summary.sport.title, systemImage: summary.sport.symbolName)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(ThemeCatalog.palette(id: summary.themeID).name).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
            }
            Spacer()
            if isActive {
                Text("Showing").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
