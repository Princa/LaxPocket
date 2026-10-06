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
    /// A parent who also coaches is looking at Coaching rather than their own athletes.
    var showsCoaching = false
    /// The currency the budget screens show amounts in, on this device. Amounts are stored and added up in CAD.
    var displayCurrency: Currency = AppStore.savedDisplayCurrency {
        didSet { UserDefaults.standard.set(displayCurrency.rawValue, forKey: AppStore.displayCurrencyKey) }
    }
    let library: ProfileLibrary
    /// Called after the user changes a profile's data, with that profile's ID. Cloud sync listens here.
    @ObservationIgnored var onLocalChange: (@MainActor (UUID) -> Void)?

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

    private static let displayCurrencyKey = "budgetDisplayCurrency"
    private static var savedDisplayCurrency: Currency {
        UserDefaults.standard.string(forKey: displayCurrencyKey).flatMap(Currency.init(rawValue:)) ?? .cad
    }

    /// A CAD amount in the display currency, converted at the athlete's exchange rate.
    func money(_ cad: Double) -> String {
        Formatters.money(ExchangeRate.shown(cad, in: displayCurrency, rate: profile.usdToCAD), currency: displayCurrency)
    }

    /// An expense in the display currency: exactly what was paid when it was paid in that currency.
    func money(_ expense: Expense) -> String {
        expense.currency == displayCurrency ? Formatters.money(expense.paidAmount, currency: displayCurrency) : money(expense.amount)
    }

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

    #if DEBUG
    /// Adds the made-up demo athlete (or rebuilds it around today) and switches to it. Debug builds only; the demo
    /// stays on this device and isn't a local change, so cloud sync never uploads it. With a `viewer`, she looks the
    /// way she would to that account in the cloud (see `DemoSeason.make(viewer:)`).
    func loadDemoAthlete(viewer: Relationship? = nil) {
        let demo = viewer.map { DemoSeason.make(now: now, viewer: $0) } ?? DemoSeason.make(now: now)
        data = demo
        index.upsert(demo.summary)
        index.activeProfileID = demo.id
        selectedTab = .home
        saveProfile()
        saveIndex()
    }
    #endif

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

    /// Adds the expense, or replaces the one with the same ID.
    func saveExpense(_ expense: Expense) {
        update { data in
            if let index = data.expenses.firstIndex(where: { $0.id == expense.id }) {
                data.expenses[index] = expense
            } else {
                data.expenses.append(expense)
            }
        }
    }

    /// Sets a season's overall budget and the program budgets for that season in one change; 0 removes one.
    func setBudgets(season: Int, overall: Double, programs: [String: Double]) {
        update { data in
            data.setBudget(overall, for: season)
            for (programID, amount) in programs { data.setProgramBudget(amount, programID: programID, season: season) }
        }
    }

    func deleteExpenses(_ ids: Set<UUID>) {
        update { $0.expenses.removeAll { ids.contains($0.id) } }
    }

    func trip(_ id: UUID) -> Trip? { data.trip(id: id) }

    /// Sets the athlete's exchange rate. With `reconvert`, US-dollar expenses are converted again at the new rate.
    func setUSDToCAD(_ rate: Double, reconvert: Bool) {
        update { $0.setUSDToCAD(rate, reconvert: reconvert) }
    }

    /// Adds the trip, or replaces the one with the same ID.
    func saveTrip(_ trip: Trip) {
        update { data in
            if let index = data.trips.firstIndex(where: { $0.id == trip.id }) {
                data.trips[index] = trip
            } else {
                data.trips.append(trip)
            }
        }
    }

    /// Deletes the trip. Its expenses are deleted with it, or kept without the link.
    func deleteTrip(_ id: UUID, withExpenses: Bool) {
        update { data in
            data.trips.removeAll { $0.id == id }
            if withExpenses {
                data.expenses.removeAll { $0.tripID == id }
            } else {
                for index in data.expenses.indices where data.expenses[index].tripID == id { data.expenses[index].tripID = nil }
            }
        }
    }

    func addCombineResult(_ result: CombineResult) {
        update { $0.combineResults.append(result) }
    }

    /// Adds the event, or replaces the one with the same ID.
    /// A trip to the event moves with it (see `AppData.moveTrips`).
    func saveEvent(_ event: SeasonEvent) {
        update { data in
            if let index = data.events.firstIndex(where: { $0.id == event.id }) {
                let old = data.events[index]
                data.events[index] = event
                data.moveTrips(from: old, to: event)
            } else {
                data.events.append(event)
            }
        }
    }

    /// Deletes the event. A trip to it stays, without the link.
    func deleteEvent(_ id: UUID) {
        update { data in
            data.events.removeAll { $0.id == id }
            for index in data.trips.indices where data.trips[index].eventID == id { data.trips[index].eventID = nil }
        }
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

    /// Only programs with no logged sessions or expenses can be deleted, so the training log and the budget never
    /// point at a missing program.
    func canDeleteProgram(_ id: String) -> Bool {
        !data.sessions.contains { $0.programID == id } && !data.expenses.contains { $0.programID == id }
    }

    /// Deletes the program and its budgets. Trips with it stay, without the link.
    func deleteProgram(_ id: String) {
        guard canDeleteProgram(id) else { return }
        update { data in
            data.programs.removeAll { $0.id == id }
            data.programBudgets.removeAll { $0.programID == id }
            for index in data.trips.indices where data.trips[index].programID == id { data.trips[index].programID = nil }
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

    /// Ticks a coach's task off for its current day, week or one-off span, or unticks it.
    func setAssignment(_ id: UUID, done: Bool, periodStart: DayKey) {
        update { $0.setAssignment(id, done: done, periodStart: periodStart) }
    }

    /// Only the athlete's own login can lock or hide a doc; the cloud refuses it from anyone else.
    func setDocVisibility(_ id: UUID, _ visibility: DocVisibility) {
        update { data in
            if let index = data.docs.firstIndex(where: { $0.id == id }) { data.docs[index].visibility = visibility }
        }
    }

    func deleteDocs(_ ids: Set<UUID>) {
        update { $0.docs.removeAll { ids.contains($0.id) } }
    }

    /// Adds the height and weight check, or replaces the one with the same ID.
    func saveBodyMeasurement(_ measurement: BodyMeasurement) {
        update { data in
            if let index = data.bodyMeasurements.firstIndex(where: { $0.id == measurement.id }) {
                data.bodyMeasurements[index] = measurement
            } else {
                data.bodyMeasurements.append(measurement)
            }
        }
    }

    func deleteBodyMeasurements(_ ids: Set<UUID>) {
        update { $0.bodyMeasurements.removeAll { ids.contains($0.id) } }
    }

    /// Adds the wall ball session, or replaces the one with the same ID.
    func saveWallballSession(_ session: WallballSession) {
        update { data in
            if let index = data.wallballSessions.firstIndex(where: { $0.id == session.id }) {
                data.wallballSessions[index] = session
            } else {
                data.wallballSessions.append(session)
            }
        }
    }

    func deleteWallballSessions(_ ids: Set<UUID>) {
        update { $0.wallballSessions.removeAll { ids.contains($0.id) } }
    }

    /// Saves a drill the athlete added or changed. A built-in put back the way it ships isn't stored.
    func saveWallballDrill(_ drill: WallballDrill) {
        update { data in
            let index = data.wallballDrills.firstIndex { $0.id == drill.id }
            if WallballCatalog.builtIn(id: drill.id) == drill {
                if let index { data.wallballDrills.remove(at: index) }
            } else if let index {
                data.wallballDrills[index] = drill
            } else {
                data.wallballDrills.append(drill)
            }
        }
    }

    /// Only the athlete's own drills with no reps logged can be deleted; the rest can be hidden.
    func canDeleteWallballDrill(_ id: String) -> Bool {
        !WallballCatalog.builtInIDs.contains(id) && !data.wallballSessions.contains { $0.sets.contains { $0.drillID == id } }
    }

    func deleteWallballDrill(_ id: String) {
        guard canDeleteWallballDrill(id) else { return }
        update { $0.wallballDrills.removeAll { $0.id == id } }
    }

    /// Puts a built-in drill back the way it ships.
    func resetWallballDrill(_ id: String) {
        guard WallballCatalog.builtInIDs.contains(id) else { return }
        update { $0.wallballDrills.removeAll { $0.id == id } }
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
