import XCTest
@testable import LaxPocketCore

final class SportProfileTests: XCTestCase {
    /// Encodes a value and drops some keys, the way a file or row saved before hockey looks.
    private func withoutKeys<T: Encodable>(_ value: T, _ keys: [String], encoder: JSONEncoder = AppData.encoder) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
        for key in keys { object.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testProfilesSavedBeforeHockeyAreLacrosse() throws {
        let sam = Fixtures.season()
        let raw = try withoutKeys(sam.profile, ["sport", "athleteID", "shoots", "playsGoal", "level"])
        let profile = try AppData.decoder.decode(AthleteProfile.self, from: raw)
        XCTAssertEqual(profile.sport, .lacrosse)
        XCTAssertNil(profile.athleteID)
        XCTAssertNil(profile.shoots)
        XCTAssertFalse(profile.playsGoal)
        XCTAssertEqual(profile.level, "")
        XCTAssertEqual(profile.firstName, "Sam")

        let summary = try AppData.decoder.decode(ProfileSummary.self, from: try withoutKeys(sam.summary, ["sport", "athleteID"]))
        XCTAssertEqual(summary, ProfileSummary(id: sam.id, name: "Sam", themeID: sam.themeID))
        XCTAssertEqual(summary.athleteKey, sam.id)
    }

    func testAddingASportCopiesOnlyTheAthlete() throws {
        var sam = Fixtures.season()
        sam.profile.bodyUnits = .metric
        sam.profile.usdToCAD = 1.41
        sam.profile.mentalCoachName = "Dr G"
        let hockey = sam.addingSport(.hockey, themeID: "navy", now: Fixtures.day(0))

        XCTAssertNotEqual(hockey.id, sam.id)
        XCTAssertEqual(hockey.athleteKey, sam.athleteKey)
        XCTAssertEqual(hockey.profile.athleteID, sam.id)
        XCTAssertEqual(hockey.profile.sport, .hockey)
        XCTAssertEqual(hockey.profile.firstName, "Sam")
        XCTAssertEqual(hockey.profile.classYear, sam.profile.classYear)
        XCTAssertEqual(hockey.profile.bodyUnits, .metric)
        XCTAssertEqual(hockey.profile.usdToCAD, 1.41)
        XCTAssertEqual(hockey.profile.season, "2026/27")
        XCTAssertEqual(hockey.themeID, "navy")
        XCTAssertEqual(hockey.profile.positions, "")
        XCTAssertEqual(hockey.profile.mentalCoachName, "")
        XCTAssertNil(hockey.profile.benchmarkGroup)
        XCTAssertTrue(hockey.programs.isEmpty && hockey.sessions.isEmpty && hockey.events.isEmpty && hockey.expenses.isEmpty
                      && hockey.bodyMeasurements.isEmpty && hockey.wallballSessions.isEmpty && hockey.docs.isEmpty,
                      "nothing is shared between sports")

        // A third sport added from the second still belongs to the same athlete.
        let third = hockey.addingSport(.lacrosse)
        XCTAssertEqual(third.athleteKey, sam.id)
    }

    func testIndexGroupsEachAthletesSports() {
        let samLacrosse = ProfileSummary(id: UUID(), name: "Sam")
        let ben = ProfileSummary(id: UUID(), name: "Ben", sport: .hockey)
        let samHockey = ProfileSummary(id: UUID(), name: "Sam", sport: .hockey, athleteID: samLacrosse.id)
        let index = ProfileIndex(profiles: [samLacrosse, ben, samHockey], activeProfileID: samHockey.id)

        XCTAssertEqual(index.athletes, [[samLacrosse, samHockey], [ben]])
        XCTAssertEqual(index.sportProfiles(of: samHockey.id), [samLacrosse, samHockey])
        XCTAssertTrue(index.hasOtherSports(samLacrosse.id))
        XCTAssertFalse(index.hasOtherSports(ben.id))
        XCTAssertEqual(samHockey.nameWithSport, "Sam · Hockey")
    }

    func testSuggestedThemeDiffersFromTheAthletesOtherSports() {
        XCTAssertEqual(AppData.suggestedTheme(besides: []), ThemeCatalog.defaultID)
        let next = AppData.suggestedTheme(besides: [ThemeCatalog.defaultID])
        XCTAssertNotEqual(next, ThemeCatalog.defaultID)
        XCTAssertTrue(ThemeCatalog.all.contains { $0.id == next })
    }

    func testFocusTagsFollowTheSport() {
        let lacrosse = AthleteProfile(firstName: "Sam", classYear: nil, positions: "", season: "2026/27")
        var hockey = lacrosse
        hockey.sport = .hockey
        XCTAssertEqual(TrainingSession.focusOptions(for: .team, athlete: lacrosse), TrainingSession.focusOptions)
        XCTAssertTrue(TrainingSession.focusOptions(for: .skills, athlete: hockey).contains("Faceoffs"))
        XCTAssertFalse(TrainingSession.focusOptions(for: .skills, athlete: hockey).contains("Draw controls"))
        hockey.playsGoal = true
        XCTAssertTrue(TrainingSession.focusOptions(for: .skills, athlete: hockey).contains("Butterfly"))
        XCTAssertFalse(TrainingSession.focusOptions(for: .skills, athlete: hockey).contains("Faceoffs"))
        XCTAssertEqual(TrainingSession.focusOptions(for: .mental, athlete: hockey), TrainingSession.mentalFocusOptions)
    }

    func testWhatEachSportHasSoFar() {
        XCTAssertTrue(Sport.lacrosse.hasWallball && Sport.lacrosse.hasNDTPTesting && Sport.lacrosse.hasGameStats)
        XCTAssertFalse(Sport.hockey.hasWallball || Sport.hockey.hasNDTPTesting || Sport.hockey.hasGameStats)
        XCTAssertFalse(RosterKind.team.sharingSummary(for: .hockey).contains("wall ball"))
        XCTAssertTrue(RosterKind.team.sharingSummary.contains("wall ball"))
    }

    func testHockeyProfileRoundTripsThroughTheCloud() {
        let sam = Fixtures.season()
        var hockey = sam.addingSport(.hockey)
        hockey.profile.shoots = .left
        hockey.profile.playsGoal = true
        hockey.profile.level = "  U15 AA  "
        let row = ProfileRow(hockey)
        XCTAssertEqual(row.sport, .hockey)
        XCTAssertEqual(row.athleteID, sam.id)
        XCTAssertEqual(row.athleteKey, sam.id)
        XCTAssertEqual(row.level, "U15 AA")

        let back = ProfileSnapshot(hockey).appData.profile
        XCTAssertEqual(back.sport, .hockey)
        XCTAssertEqual(back.athleteID, sam.id)
        XCTAssertEqual(back.shoots, .left)
        XCTAssertTrue(back.playsGoal)
        XCTAssertEqual(back.level, "U15 AA")
    }

    func testRowsKeepToWhatTheDatabaseTakes() {
        var sam = Fixtures.season()
        sam.profile.shoots = .right
        sam.profile.playsGoal = true
        sam.profile.athleteID = sam.id
        var row = ProfileRow(sam)
        XCTAssertNil(row.shoots, "only hockey has a shooting side")
        XCTAssertFalse(row.playsGoal)
        XCTAssertNil(row.athleteID, "an athlete's first profile has no athlete_id")
        sam.profile.sport = .hockey
        sam.profile.level = String(repeating: "A", count: 60)
        row = ProfileRow(sam)
        XCTAssertEqual(row.level.count, 40)
    }

    func testRowsSavedBeforeHockeyAreLacrosse() throws {
        let sam = Fixtures.season()
        let raw = try withoutKeys(ProfileRow(sam), ["sport", "athlete_id", "shoots", "plays_goal", "level"], encoder: JSONEncoder())
        let row = try JSONDecoder().decode(ProfileRow.self, from: raw)
        XCTAssertEqual(row.sport, .lacrosse)
        XCTAssertNil(row.athleteID)

        let roster = try JSONDecoder().decode(RosterRow.self, from: Data(#"{"id":"\#(UUID())","kind":"team","name":"U15","join_code":null}"#.utf8))
        XCTAssertEqual(roster.sport, .lacrosse)
        let hockeyRoster = try JSONDecoder().decode(
            RosterRow.self, from: Data(#"{"id":"\#(UUID())","kind":"team","name":"U15 AA","join_code":"ABCD2345","sport":"hockey"}"#.utf8))
        XCTAssertEqual(hockeyRoster.sport, .hockey)

        let code = try JSONDecoder().decode(CodeInfo.self, from: Data(#"{"type":"roster","roster":"U15 AA","kind":"team","coach":"Fay","sport":"hockey"}"#.utf8))
        XCTAssertEqual(code, .roster(name: "U15 AA", kind: .team, coachName: "Fay", sport: .hockey))

        let athlete = try JSONDecoder().decode(CoachAthleteProfileRow.self, from: Data(
            #"{"id":"\#(UUID())","first_name":"Sam","class_year":2031,"positions":"","benchmark_group":null,"weekly_goal_hours":12,"theme_id":"original"}"#.utf8))
        XCTAssertEqual(athlete.sport, .lacrosse)
    }

    func testCoachSeesTheRostersSport() {
        let sam = Fixtures.season()
        var hockey = sam.addingSport(.hockey)
        hockey.profile.level = "U15 AA"
        let roster = RosterRow(id: UUID(), kind: .team, name: "U15 AA", joinCode: "ABCD2345", sport: .hockey)
        var rows = CoachWorkspace.Rows()
        rows.profiles = [CoachAthleteProfileRow(id: hockey.id, firstName: "Sam", classYear: nil, positions: "Centre", benchmarkGroup: nil,
                                                weeklyGoalHours: 10, themeID: "navy", sport: .hockey, shoots: .left, level: "U15 AA")]
        let rosters = CoachWorkspace.assemble(rosters: [roster], places: [RosterAthleteRow(rosterID: roster.id, profileID: hockey.id)], rows: rows)
        XCTAssertEqual(rosters[0].sport, .hockey)
        let athlete = rosters[0].athletes[0].data.profile
        XCTAssertEqual(athlete.sport, .hockey)
        XCTAssertEqual(athlete.shoots, .left)
        XCTAssertEqual(athlete.level, "U15 AA")
    }
}
