import Foundation

/// One sport profile in the profile list: enough to show the switcher without loading their data.
public struct ProfileSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var themeID: String
    public var sport: Sport
    /// See `AthleteProfile.athleteID`.
    public var athleteID: UUID?

    public init(id: UUID, name: String, themeID: String = ThemeCatalog.defaultID, sport: Sport = .lacrosse, athleteID: UUID? = nil) {
        self.id = id
        self.name = name
        self.themeID = themeID
        self.sport = sport
        self.athleteID = athleteID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, themeID, sport, athleteID
    }

    /// Lists saved before hockey have no `sport` or `athleteID`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? ThemeCatalog.defaultID
        sport = try c.decodeIfPresent(Sport.self, forKey: .sport) ?? .lacrosse
        athleteID = try c.decodeIfPresent(UUID.self, forKey: .athleteID)
    }

    /// The same for every sport profile of one athlete.
    public var athleteKey: UUID { athleteID ?? id }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Unnamed athlete" : trimmed
    }

    /// "Maya · Hockey", for lists where an athlete's sports sit side by side.
    public var nameWithSport: String {
        "\(displayName) · \(sport.title)"
    }

    /// First letter of the name for avatar badges.
    public var initial: String {
        displayName.first.map { String($0).uppercased() } ?? "?"
    }
}

/// The list of athlete profiles on this device and which one is showing.
public struct ProfileIndex: Codable, Equatable, Sendable {
    public var profiles: [ProfileSummary]
    public var activeProfileID: UUID?

    public init(profiles: [ProfileSummary] = [], activeProfileID: UUID? = nil) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
    }

    public var active: ProfileSummary? {
        profiles.first { $0.id == activeProfileID }
    }

    /// Each athlete's sport profiles, athletes in the order they were added and each one's sports in the same order.
    public var athletes: [[ProfileSummary]] {
        var order: [UUID] = []
        var byAthlete: [UUID: [ProfileSummary]] = [:]
        for summary in profiles {
            if byAthlete[summary.athleteKey] == nil { order.append(summary.athleteKey) }
            byAthlete[summary.athleteKey, default: []].append(summary)
        }
        return order.compactMap { byAthlete[$0] }
    }

    /// Every sport profile of the athlete a profile belongs to, itself included.
    public func sportProfiles(of id: UUID) -> [ProfileSummary] {
        guard let key = profiles.first(where: { $0.id == id })?.athleteKey else { return [] }
        return profiles.filter { $0.athleteKey == key }
    }

    /// True when the athlete a profile belongs to plays more than one sport on this phone.
    public func hasOtherSports(_ id: UUID) -> Bool {
        sportProfiles(of: id).count > 1
    }

    /// Replaces the summary with the same ID, or appends it.
    public mutating func upsert(_ summary: ProfileSummary) {
        if let index = profiles.firstIndex(where: { $0.id == summary.id }) {
            profiles[index] = summary
        } else {
            profiles.append(summary)
        }
    }

    /// Removes a profile. If it was active, the first remaining profile becomes active.
    public mutating func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id || !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles.first?.id
        }
    }
}

/// Stores each athlete profile as its own JSON file, plus a small index.
///
///     <directory>/profiles.json          which profiles exist, in order, and the active one
///     <directory>/profiles/<id>.json     one `AppData` per athlete
///     <directory>/sync/<id>.json         see `loadSyncBase(_:)`
public struct ProfileLibrary {
    public let directory: URL
    /// Extra options for every write, e.g. `.completeFileProtection` on iOS.
    public var writeOptions: Data.WritingOptions

    public init(directory: URL, writeOptions: Data.WritingOptions = []) {
        self.directory = directory
        self.writeOptions = writeOptions
    }

    public var indexURL: URL { directory.appendingPathComponent("profiles.json") }
    var profilesDirectory: URL { directory.appendingPathComponent("profiles", isDirectory: true) }

    public func profileURL(_ id: UUID) -> URL {
        profilesDirectory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    // MARK: - Index

    /// The saved index, repaired against the profile files on disk: entries without a file are dropped
    /// and files missing from the index are added back.
    public func loadIndex() -> ProfileIndex {
        var index = (try? Data(contentsOf: indexURL)).flatMap { try? AppData.decoder.decode(ProfileIndex.self, from: $0) } ?? ProfileIndex()
        let onDisk = storedProfileIDs()
        index.profiles.removeAll { !onDisk.contains($0.id) }
        for id in onDisk.sorted(by: { $0.uuidString < $1.uuidString }) where !index.profiles.contains(where: { $0.id == id }) {
            if let data = try? loadProfile(id) { index.upsert(data.summary) }
        }
        if index.active == nil { index.activeProfileID = index.profiles.first?.id }
        return index
    }

    public func saveIndex(_ index: ProfileIndex) throws {
        try write(index, to: indexURL)
    }

    private func storedProfileIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: profilesDirectory.path)) ?? []
        return Set(names.compactMap { name in
            name.hasSuffix(".json") ? UUID(uuidString: String(name.dropLast(5))) : nil
        })
    }

    // MARK: - Profiles

    public func loadProfile(_ id: UUID) throws -> AppData {
        let raw = try Data(contentsOf: profileURL(id))
        var data = try AppData.decoder.decode(AppData.self, from: raw)
        data.id = id
        return data
    }

    public func saveProfile(_ data: AppData) throws {
        try write(data, to: profileURL(data.id))
    }

    /// Removes the profile's data, and its sync record, from this device.
    public func deleteProfile(_ id: UUID) throws {
        let url = profileURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try removeSyncBase(id)
    }

    // MARK: - Version 1 files

    /// Moves a version 1 `season.json` into the library as a profile and removes the old file.
    ///
    /// The built-in sample season (`"isSample": true`) is not kept. Returns the imported profile, or nil
    /// when there was nothing to import.
    @discardableResult
    public func importLegacySeason(at url: URL) throws -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let flags = try? AppData.decoder.decode(LegacyFlags.self, from: raw)
        var imported: AppData?
        if flags?.isSample != true {
            let data = try AppData.decoder.decode(AppData.self, from: raw)
            try saveProfile(data)
            var index = loadIndex()
            index.upsert(data.summary)
            index.activeProfileID = data.id
            try saveIndex(index)
            imported = data
        }
        try FileManager.default.removeItem(at: url)
        return imported
    }

    private struct LegacyFlags: Decodable {
        var isSample: Bool?
    }

    // MARK: - Files

    func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let raw = try AppData.encoder.encode(value)
        try raw.write(to: url, options: writeOptions.union(.atomic))
    }
}
