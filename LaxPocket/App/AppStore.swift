import Foundation
import Observation
import LaxPocketCore
#if canImport(UIKit)
import UIKit
#endif

/// Holds the athlete profiles on this device and the active profile's data.
/// Each profile is saved as its own JSON file in Application Support after every change.
@MainActor
@Observable
final class AppStore {
    /// The active profile's data, or a blank placeholder while no profile exists.
    private(set) var data: AppData
    private(set) var index: ProfileIndex
    /// Which tab is showing (not saved).
    var selectedTab: AppTab = .home
    let library: ProfileLibrary
    /// Called after the user changes a profile's data, with that profile's ID. Cloud sync listens here.
    @ObservationIgnored var onLocalChange: ((UUID) -> Void)?

    init(library: ProfileLibrary = AppStore.defaultLibrary, legacyFileURL: URL? = AppStore.legacyFileURL) {
        self.library = library
        if let legacyFileURL {
            do {
                try library.importLegacySeason(at: legacyFileURL)
            } catch {
                print("LaxPocket: could not import the old season file – \(error)")
            }
        }
        var index = library.loadIndex()
        var data = AppData.placeholder
        for id in [index.activeProfileID].compactMap({ $0 }) + index.profiles.map(\.id) {
            if let loaded = try? library.loadProfile(id) {
                data = loaded
                index.activeProfileID = id
                break
            }
        }
        if data.id == AppData.placeholder.id { index.activeProfileID = nil }
        self.index = index
        self.data = data
    }

    // MARK: - Derived

    var palette: ThemePalette { ThemeCatalog.palette(id: data.themeID) }
    var profile: AthleteProfile { data.profile }
    var profiles: [ProfileSummary] { index.profiles }
    var hasProfile: Bool { index.activeProfileID != nil }
    var now: Date { Date() }

    func program(_ id: String) -> Program? { data.program(id: id) }

    // MARK: - Profiles

    /// Saves a new profile and switches to it.
    func createProfile(_ newData: AppData) {
        data = newData
        index.upsert(newData.summary)
        index.activeProfileID = newData.id
        selectedTab = .home
        saveProfile()
        saveIndex()
        onLocalChange?(newData.id)
    }

    func switchProfile(to id: UUID) {
        guard id != index.activeProfileID else { return }
        do {
            data = try library.loadProfile(id)
            index.activeProfileID = id
            selectedTab = .home
            saveIndex()
        } catch {
            print("LaxPocket: could not open profile – \(error)")
        }
    }

    /// Removes a profile and its data from this device. Switches to another profile if it was showing.
    func deleteProfile(_ id: UUID) {
        do {
            try library.deleteProfile(id)
        } catch {
            print("LaxPocket: could not delete profile – \(error)")
            return
        }
        let wasActive = id == index.activeProfileID
        index.remove(id)
        if wasActive {
            data = index.activeProfileID.flatMap { try? library.loadProfile($0) } ?? AppData.placeholder
            if data.id == AppData.placeholder.id { index.activeProfileID = nil }
            selectedTab = .home
        }
        saveIndex()
    }

    /// A profile's data, whether or not it is the active one.
    func profileData(_ id: UUID) -> AppData? {
        if id == data.id { return data }
        return try? library.loadProfile(id)
    }

    /// Stores data that came from the cloud. Does not count as a local change.
    func replaceProfileData(_ newData: AppData) {
        let isKnown = index.profiles.contains { $0.id == newData.id }
        if newData.id == data.id { data = newData }
        do {
            try library.saveProfile(newData)
        } catch {
            print("LaxPocket: could not save profile – \(error)")
        }
        index.upsert(newData.summary)
        if !isKnown && index.activeProfileID == nil {
            index.activeProfileID = newData.id
            data = newData
        }
        saveIndex()
    }

    // MARK: - Mutations

    func update(_ change: (inout AppData) -> Void) {
        guard hasProfile else { return }
        let before = data.summary
        change(&data)
        saveProfile()
        if data.summary != before {
            index.upsert(data.summary)
            saveIndex()
        }
        onLocalChange?(data.id)
    }

    func addSession(_ session: TrainingSession) {
        update { $0.sessions.append(session) }
    }

    func deleteSessions(_ ids: Set<UUID>) {
        update { $0.sessions.removeAll { ids.contains($0.id) } }
    }

    func addExpense(_ expense: Expense) {
        update { $0.expenses.append(expense) }
    }

    func deleteExpenses(_ ids: Set<UUID>) {
        update { $0.expenses.removeAll { ids.contains($0.id) } }
    }

    func addCombineResult(_ result: CombineResult) {
        update { $0.combineResults.append(result) }
    }

    /// Adds the event, or replaces the one with the same ID.
    func saveEvent(_ event: SeasonEvent) {
        update { data in
            if let index = data.events.firstIndex(where: { $0.id == event.id }) {
                data.events[index] = event
            } else {
                data.events.append(event)
            }
        }
    }

    func deleteEvent(_ id: UUID) {
        update { $0.events.removeAll { $0.id == id } }
    }

    /// Adds the program, or replaces the one with the same ID.
    func saveProgram(_ program: Program) {
        update { data in
            if let index = data.programs.firstIndex(where: { $0.id == program.id }) {
                data.programs[index] = program
            } else {
                data.programs.append(program)
            }
        }
    }

    /// Only programs with no logged sessions can be deleted, so the training log never points at a missing program.
    func canDeleteProgram(_ id: String) -> Bool {
        !data.sessions.contains { $0.programID == id }
    }

    func deleteProgram(_ id: String) {
        guard canDeleteProgram(id) else { return }
        update { $0.programs.removeAll { $0.id == id } }
    }

    func addDoc(_ doc: MentalDoc) {
        update { $0.docs.insert(doc, at: 0) }
    }

    func setDocStatus(_ id: UUID, _ status: DocStatus) {
        update { data in
            if let index = data.docs.firstIndex(where: { $0.id == id }) { data.docs[index].status = status }
        }
    }

    func deleteDocs(_ ids: Set<UUID>) {
        update { $0.docs.removeAll { ids.contains($0.id) } }
    }

    func setTheme(_ palette: ThemePalette) {
        update { $0.themeID = palette.id }
        applyAppIcon(for: palette)
    }

    func startBlankSeason() {
        update { $0 = $0.blankSeason() }
    }

    // MARK: - App icon

    /// Switches the home-screen icon to match the theme (iOS asks the user to confirm).
    func applyAppIcon(for palette: ThemePalette) {
        #if canImport(UIKit)
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != palette.alternateIconName else { return }
        app.setAlternateIconName(palette.alternateIconName) { error in
            if let error { print("LaxPocket: could not change app icon – \(error.localizedDescription)") }
        }
        #endif
    }

    // MARK: - Persistence

    nonisolated static var baseDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LaxPocket", isDirectory: true)
    }

    nonisolated static var defaultLibrary: ProfileLibrary {
        ProfileLibrary(directory: baseDirectory, writeOptions: .completeFileProtection)
    }

    /// Where version 0.1 kept its single season file.
    nonisolated static var legacyFileURL: URL {
        baseDirectory.appendingPathComponent("season.json")
    }

    private func saveProfile() {
        do {
            try library.saveProfile(data)
        } catch {
            print("LaxPocket: could not save profile – \(error)")
        }
    }

    private func saveIndex() {
        do {
            try library.saveIndex(index)
        } catch {
            print("LaxPocket: could not save profile list – \(error)")
        }
    }
}
