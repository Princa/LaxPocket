import SwiftUI
import LaxPocketCore

/// The clubs and teams the current athlete plays for. Each one is a Teams & leagues program.
struct ClubsView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let id = UUID()
        var club: Program?
    }

    var body: some View {
        let clubs = store.data.clubs
        let hours = store.data.hoursByProgram
        List {
            Section {
                ForEach(clubs) { club in
                    Button { editing = EditTarget(club: club) } label: {
                        HStack(spacing: 12) {
                            Text(club.monogram)
                                .font(.display(15))
                                .frame(width: 36, height: 36)
                                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(club.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                if !club.detail.isEmpty {
                                    Text(club.detail).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                                }
                            }
                            Spacer()
                            if let h = hours[club.id], h > 0 {
                                Text("\(Formatters.hours(h)) h").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .deleteDisabled(!store.canDeleteProgram(club.id))
                }
                .onDelete { offsets in
                    for index in offsets { store.deleteProgram(clubs[index].id) }
                }
                if clubs.isEmpty {
                    Text("No clubs yet.").foregroundStyle(AppTheme.caption)
                }
            } footer: {
                Text("Tap to rename or edit. Clubs with logged sessions can’t be deleted until those sessions are.")
            }

            Section {
                Button { editing = EditTarget() } label: { Label("Add a club or team", systemImage: "plus") }
            }
        }
        .navigationTitle("Clubs & teams")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in ProgramEditorView(program: target.club, group: .teams) }
    }
}
