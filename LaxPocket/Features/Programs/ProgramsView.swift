import SwiftUI
import LaxPocketCore

struct ProgramsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme

    var body: some View {
        let hours = store.data.hoursByProgram
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: "Programs")
                    Text("Teams, coaches & facilities · hours this season").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
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

        switch group {
        case .mental:
            NavigationLink { MindsetView() } label: { content }.buttonStyle(.plain)
        case .combine:
            Button { store.selectedTab = .metrics } label: { content }.buttonStyle(.plain)
        default:
            content
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
