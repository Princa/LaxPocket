import SwiftUI
import LaxPocketCore

/// Lists the athlete profiles on this iPhone: switch, add or remove.
struct ProfilesView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudStore.self) private var cloud
    @State private var showNew = false
    @State private var pendingDelete: ProfileSummary?

    var body: some View {
        List {
            Section {
                ForEach(store.profiles) { summary in
                    Button { store.switchProfile(to: summary.id) } label: { row(summary) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = summary }
                        }
                        .accessibilityAddTraits(summary.id == store.data.id ? .isSelected : [])
                }
            } footer: {
                Text("Each athlete has their own sessions, results, events, budget and documents. Tap to switch; swipe to delete.")
            }

            Section {
                Button { showNew = true } label: { Label("Add athlete", systemImage: "person.badge.plus") }
            }
        }
        .navigationTitle("Athletes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNew) { NewProfileView() }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDelete) { summary in
            Button("Delete \(summary.displayName)", role: .destructive) { store.deleteProfile(summary.id) }
        } message: { summary in
            Text(cloud.isSignedIn
                 ? "Removes \(summary.displayName) from this iPhone. The copy in your cloud account stays; delete it from Cloud sync if you want it gone everywhere."
                 : "Removes \(summary.displayName)’s profile, sessions, results, events, expenses and linked docs from this iPhone. This can’t be undone.")
        }
    }

    private var deleteTitle: String {
        "Delete \(pendingDelete?.displayName ?? "this athlete")?"
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func row(_ summary: ProfileSummary) -> some View {
        let isActive = summary.id == store.data.id
        return HStack(spacing: 12) {
            ProfileAvatar(summary: summary)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(AppTheme.ink)
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
