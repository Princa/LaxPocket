import XCTest
@testable import LaxPocketCore

final class ProfileLibraryTests: XCTestCase {
    private var directory: URL!
    private var library: ProfileLibrary { ProfileLibrary(directory: directory) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LaxPocketTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEmptyLibrary() {
        let index = library.loadIndex()
        XCTAssertTrue(index.profiles.isEmpty)
        XCTAssertNil(index.activeProfileID)
    }

    func testEachProfileKeepsItsOwnData() throws {
        let sam = Fixtures.season(name: "Sam")
        var alex = AppData.newProfile(AthleteProfile(firstName: "Alex", classYear: 2033, positions: "Goalie", benchmarkGroup: .u15Men, season: "2026/27"))
        alex.expenses = [Expense(date: Fixtures.day(0), title: "Goalie pads", category: .equipment, amount: 400)]
        try library.saveProfile(sam)
        try library.saveProfile(alex)
        try library.saveIndex(ProfileIndex(profiles: [sam.summary, alex.summary], activeProfileID: alex.id))

        let index = library.loadIndex()
        XCTAssertEqual(index.profiles.map(\.name), ["Sam", "Alex"])
        XCTAssertEqual(index.activeProfileID, alex.id)

        let loadedSam = try library.loadProfile(sam.id)
        let loadedAlex = try library.loadProfile(alex.id)
        XCTAssertEqual(loadedSam.sessions.count, 3)
        XCTAssertEqual(loadedSam.expenses.count, 2)
        XCTAssertTrue(loadedAlex.sessions.isEmpty)
        XCTAssertEqual(loadedAlex.expenses.map(\.title), ["Goalie pads"])
        XCTAssertEqual(loadedAlex.profile.benchmarkGroup, .u15Men)
    }

    func testDeleteProfile() throws {
        let sam = Fixtures.season(name: "Sam")
        let alex = Fixtures.season(name: "Alex")
        try library.saveProfile(sam)
        try library.saveProfile(alex)
        var index = ProfileIndex(profiles: [sam.summary, alex.summary], activeProfileID: sam.id)
        index.remove(sam.id)
        try library.saveIndex(index)
        try library.deleteProfile(sam.id)

        XCTAssertEqual(index.activeProfileID, alex.id)
        XCTAssertThrowsError(try library.loadProfile(sam.id))
        XCTAssertEqual(library.loadIndex().profiles.map(\.id), [alex.id])
    }

    /// A lost or stale index is rebuilt from the profile files.
    func testIndexIsRepairedFromFiles() throws {
        let sam = Fixtures.season(name: "Sam")
        try library.saveProfile(sam)
        let ghost = ProfileSummary(id: UUID(), name: "Ghost")
        try library.saveIndex(ProfileIndex(profiles: [ghost], activeProfileID: ghost.id))

        let index = library.loadIndex()
        XCTAssertEqual(index.profiles.map(\.id), [sam.id])
        XCTAssertEqual(index.activeProfileID, sam.id)
    }

    func testIndexUpsertAndRemove() {
        var index = ProfileIndex()
        let a = ProfileSummary(id: UUID(), name: "A")
        let b = ProfileSummary(id: UUID(), name: "B")
        index.upsert(a)
        index.upsert(b)
        index.upsert(ProfileSummary(id: a.id, name: "A2", themeID: "navy"))
        XCTAssertEqual(index.profiles.map(\.name), ["A2", "B"])
        index.activeProfileID = b.id
        index.remove(a.id)
        XCTAssertEqual(index.activeProfileID, b.id)
        index.remove(b.id)
        XCTAssertNil(index.activeProfileID)
        XCTAssertEqual(ProfileSummary(id: UUID(), name: "  ").displayName, "Unnamed athlete")
        XCTAssertEqual(ProfileSummary(id: UUID(), name: "olivia").initial, "O")
    }

    func testImportsVersion1SeasonFile() throws {
        var legacy = Fixtures.season(name: "Sam")
        legacy.sessions.removeLast()
        let legacyURL = directory.appendingPathComponent("season.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AppData.encoder.encode(legacy).write(to: legacyURL)

        let imported = try XCTUnwrap(library.importLegacySeason(at: legacyURL))
        XCTAssertEqual(imported.profile.firstName, "Sam")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        let index = library.loadIndex()
        XCTAssertEqual(index.activeProfileID, imported.id)
        XCTAssertEqual(try library.loadProfile(imported.id).sessions.count, 2)
    }

    func testDropsVersion1SampleSeason() throws {
        let legacyURL = directory.appendingPathComponent("season.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(Fixtures.season())) as? [String: Any])
        object["isSample"] = true
        try JSONSerialization.data(withJSONObject: object).write(to: legacyURL)

        XCTAssertNil(try library.importLegacySeason(at: legacyURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(library.loadIndex().profiles.isEmpty)
    }

    func testNoLegacyFile() throws {
        XCTAssertNil(try library.importLegacySeason(at: directory.appendingPathComponent("season.json")))
    }
}
