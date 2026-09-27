import SwiftUI
import LaxPocketCore

struct ProgramsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var editing: EditTarget?

    /// Which program the editor sheet is for.
    private struct EditTarget: Identifiable {
        let id = UUID()
        var program: Program?
        var group: ProgramGroup = .teams
    }

    var body: some View {
        let hours = store.data.hoursByProgram
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: "Programs")
                    Text("Teams, coaches & facilities · hours this season").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                }
                if store.data.programs.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No programs yet").font(.system(size: 17, weight: .semibold))
                            Text("Add each team, private coach, gym or facility, plus showcases, the mental coach and combine testing. Sessions are logged against them.")
                                .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Add a program") { editing = EditTarget() }
                                .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                                .padding(.top, 6)
                        }
                    }
                }
                ForEach(ProgramGroup.allCases) { group in
                    let programs = store.data.programs.filter { $0.group == group }
                    if !programs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: group.title, color: AppTheme.caption).padding(.horizontal, 4)
                            Card(padding: 0) {
                                ForEach(Array(programs.enumerated()), id: \.element.id) { index, program in
                                    row(program, group: group, hours: hours[program.id])
                                        .padding(.horizontal, 14)
                                    if index < programs.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = EditTarget() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a program")
            }
        }
        .sheet(item: $editing) { target in ProgramEditorView(program: target.program, group: target.group) }
    }

    @ViewBuilder
    private func row(_ program: Program, group: ProgramGroup, hours: Double?) -> some View {
        let content = HStack(spacing: 12) {
            Monogram(text: program.monogram, background: badgeBackground(group), foreground: badgeForeground(group))
            VStack(alignment: .leading, spacing: 2) {
                Text(program.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(program.detail).font(.system(size: 13)).foregroundStyle(AppTheme.caption)
            }
            Spacer()
            trailing(program, group: group, hours: hours)
        }
        .padding(.vertical, 12)

        Group {
            switch group {
            case .mental:
                NavigationLink { MindsetView() } label: { content }.buttonStyle(.plain)
            case .combine:
                Button { store.selectedTab = .metrics } label: { content }.buttonStyle(.plain)
            default:
                Button { editing = EditTarget(program: program) } label: { content }.buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button { editing = EditTarget(program: program) } label: { Label("Edit", systemImage: "pencil") }
            if store.canDeleteProgram(program.id) {
                Button(role: .destructive) { store.deleteProgram(program.id) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder
    private func trailing(_ program: Program, group: ProgramGroup, hours: Double?) -> some View {
        switch group {
        case .mental:
            HStack(spacing: 6) {
                Text("\(store.data.docs.count) docs").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.chevron)
            }
        case .combine:
            HStack(spacing: 6) {
                Text("\(store.data.combineResults.count) tests").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.chevron)
            }
        case .showcases:
            Text("Showcase").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.accentText)
        default:
            if let hours, hours > 0 {
                Text("\(Formatters.hours(hours)) h").font(.display(18)).foregroundStyle(AppTheme.ink)
            } else if group == .teams {
                Text("Games").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
        }
    }

    private func badgeBackground(_ group: ProgramGroup) -> Color {
        switch group {
        case .skills, .mental: return theme.accentTint
        case .showcases: return AppTheme.ink
        default: return theme.primaryTint
        }
    }

    private func badgeForeground(_ group: ProgramGroup) -> Color {
        switch group {
        case .skills, .mental: return theme.accentText
        case .showcases: return .white
        default: return theme.primary
        }
    }
}
