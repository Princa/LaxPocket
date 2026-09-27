import Foundation

/// What the cloud held for each profile after its last sync, stored next to the profiles:
///
///     <directory>/sync/<id>.json
///
/// The merge compares against it to tell "changed here" from "changed in the cloud".
extension ProfileLibrary {
    var syncDirectory: URL { directory.appendingPathComponent("sync", isDirectory: true) }

    func syncBaseURL(_ id: UUID) -> URL {
        syncDirectory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    /// Nil if the profile has never synced on this device.
    public func loadSyncBase(_ id: UUID) -> ProfileSnapshot? {
        guard let raw = try? Data(contentsOf: syncBaseURL(id)) else { return nil }
        return try? AppData.decoder.decode(ProfileSnapshot.self, from: raw)
    }

    public func saveSyncBase(_ snapshot: ProfileSnapshot, for id: UUID) throws {
        try write(snapshot, to: syncBaseURL(id))
    }

    /// Forgets the sync record, e.g. after signing out or deleting the profile.
    public func removeSyncBase(_ id: UUID) throws {
        let url = syncBaseURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
