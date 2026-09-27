import Foundation
import Observation
import LaxPocketCore
#if canImport(UIKit)
import UIKit
#endif

/// Holds the season and saves it as JSON in Application Support after every change.
@MainActor
@Observable
final class AppStore {
    private(set) var data: AppData
    /// Which tab is showing (not saved).
    var selectedTab: AppTab = .home
    private let fileURL: URL

    init(fileURL: URL = AppStore.defaultFileURL) {
        self.fileURL = fileURL
        if let saved = AppStore.load(from: fileURL) {
            data = saved
        } else {
            data = SampleData.make()
        }
    }

    // MARK: - Derived

    var palette: ThemePalette { ThemeCatalog.palette(id: data.themeID) }
    var profile: AthleteProfile { data.profile }
    var now: Date { Date() }

    func program(_ id: String) -> Program? { data.program(id: id) }

    // MARK: - Mutations

    func update(_ change: (inout AppData) -> Void) {
        change(&data)
        save()
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

    func addEvent(_ event: SeasonEvent) {
        update { $0.events.append(event) }
    }

    func updateEvent(_ event: SeasonEvent) {
        update { data in
            if let index = data.events.firstIndex(where: { $0.id == event.id }) { data.events[index] = event }
        }
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

    func reloadSampleSeason() {
        let themeID = data.themeID
        update { data in
            data = SampleData.make()
            data.themeID = themeID
        }
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

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LaxPocket", isDirectory: true).appendingPathComponent("season.json")
    }

    private static func load(from url: URL) -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        do {
            return try AppData.decoder.decode(AppData.self, from: raw)
        } catch {
            print("LaxPocket: could not read saved season – \(error)")
            return nil
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let raw = try AppData.encoder.encode(data)
            try raw.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("LaxPocket: could not save season – \(error)")
        }
    }
}
