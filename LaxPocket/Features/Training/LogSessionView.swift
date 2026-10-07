import SwiftUI
import LaxPocketCore

struct LogSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var category: SessionCategory
    @State private var programID: String?
    @State private var date = Date()
    @State private var minutes = 60
    @State private var effort = 6
    @State private var focus: Set<String> = []
    @State private var notes = ""
    @State private var showAddProgram = false

    init(category: SessionCategory = .skills) {
        _category = State(initialValue: category)
    }

    private var programs: [Program] {
        store.data.programs.filter { $0.loggedCategory == category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Type") {
                        Picker("Type", selection: $category) {
                            ForEach(SessionCategory.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    section("Program") {
                        VStack(spacing: 8) {
                            ForEach(programs) { program in
                                programButton(program)
                            }
                            if programs.isEmpty {
                                Text("No \(category.title.lowercased()) programs yet.")
                                    .font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button { showAddProgram = true } label: {
                                Label("Add a program", systemImage: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                    }

                    Card(padding: 0, radius: 14) {
                        DatePicker("Date & start", selection: $date, in: ...Date().addingTimeInterval(86_400))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        Divider().overlay(AppTheme.line).padding(.leading, 14)
                        HStack {
                            Text("Duration")
                            Spacer()
                            Button { minutes = max(15, minutes - 15) } label: { stepIcon("minus") }
                                .accessibilityLabel("Decrease duration by 15 minutes")
                            Text(durationText)
                                .font(.display(24))
                                .frame(minWidth: 96)
                            Button { minutes = min(240, minutes + 15) } label: { stepIcon("plus") }
                                .accessibilityLabel("Increase duration by 15 minutes")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    section("Effort (RPE)", trailing: "\(effort) · \(TrainingSession.effortLabel(effort))") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(1...10, id: \.self) { value in
                                Button { effort = value } label: {
                                    Text("\(value)")
                                        .font(.display(20))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(effort == value ? .white : AppTheme.ink)
                                        .background(effort == value ? theme.primary : AppTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(effort == value ? theme.primary : AppTheme.border))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Effort \(value) of 10")
                                .accessibilityAddTraits(effort == value ? .isSelected : [])
                            }
                        }
                    }

                    section("Focus") {
                        FlowLayout(spacing: 8) {
                            ForEach(focusOptions, id: \.self) { tag in
                                ChipButton(title: tag, isOn: focus.contains(tag), style: .accent) {
                                    if focus.contains(tag) { focus.remove(tag) } else { focus.insert(tag) }
                                }
                            }
                        }
                    }

                    section("Notes") {
                        TextField(notesPrompt, text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.border))
                    }

                    VStack(spacing: 10) {
                        Text("Session load: \(minutes) min × effort \(effort) = \(minutes * effort)")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.muted)
                        Button("Save session", action: save)
                            .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                            .disabled(selectedProgramID == nil)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle("Log session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(selectedProgramID == nil)
                }
            }
            .sheet(isPresented: $showAddProgram) { ProgramEditorView(group: programGroup) }
            .onChange(of: category) { _, _ in programID = programs.first?.id }
            .onAppear { if programID == nil { programID = programs.first?.id } }
        }
    }

    /// The Programs group a new program for this session type goes in.
    private var programGroup: ProgramGroup {
        switch category {
        case .team: return .teams
        case .skills: return .skills
        case .fitness: return .fitness
        case .mental: return .mental
        }
    }

    private var focusOptions: [String] { TrainingSession.focusOptions(for: category, athlete: store.profile) }

    private var notesPrompt: String {
        category == .mental
            ? "Game plan, cues to remember, how you'll prepare for the next game"
            : "What clicked? What to work on next time?"
    }

    private var selectedProgramID: String? {
        if let programID, programs.contains(where: { $0.id == programID }) { return programID }
        return programs.first?.id
    }

    private var durationText: String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }

    private func save() {
        guard let id = selectedProgramID else { return }
        store.addSession(TrainingSession(date: date, programID: id, category: category, minutes: minutes, effort: effort,
                                         focus: focusOptions.filter { focus.contains($0) },
                                         notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)))
        dismiss()
    }

    private func programButton(_ program: Program) -> some View {
        let isOn = program.id == selectedProgramID
        return Button { programID = program.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name).font(.system(size: 15, weight: .semibold))
                    Text(program.detail).font(.system(size: 13)).foregroundStyle(isOn ? theme.onPrimary : AppTheme.caption)
                }
                Spacer()
                if isOn { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)) }
            }
            .foregroundStyle(isOn ? .white : AppTheme.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isOn ? theme.primary : AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isOn ? theme.primary : AppTheme.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .frame(width: 44, height: 44)
            .background(AppTheme.background, in: Circle())
    }

    private func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: title, color: AppTheme.caption)
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.primary)
                }
            }
            content()
        }
    }
}
