import XCTest
@testable import LaxPocketCore

final class NDTPTests: XCTestCase {
    func testNewProfilesHaveNoNDTPGroup() {
        let profile = AthleteProfile(firstName: "Sam", classYear: 2031, positions: "", season: "2026/27")
        XCTAssertNil(profile.benchmarkGroup)
        let data = AppData.newProfile(profile)
        XCTAssertNil(data.ndtpProgram)
        XCTAssertTrue(data.programs.isEmpty)
    }

    func testJoiningNDTPAddsTheTeam() {
        var data = AppData.newProfile(AthleteProfile(firstName: "Sam", classYear: 2031, positions: "", season: "2026/27"))
        data.setNDTPGroup(.u15Women)
        XCTAssertEqual(data.profile.benchmarkGroup, .u15Women)
        let team = try? XCTUnwrap(data.ndtpProgram)
        XCTAssertEqual(team?.name, "NDTP")
        XCTAssertEqual(team?.group, .teams)
        XCTAssertEqual(team?.sessionCategory, .team)
        XCTAssertEqual(team?.detail, "National Development Team Program · U15 Women")

        // Moving up an age group keeps the one team.
        data.setNDTPGroup(.u17Women)
        XCTAssertEqual(data.programs.filter { $0.id == AppData.ndtpProgramID }.count, 1)
        XCTAssertEqual(data.ndtpProgram?.detail, "National Development Team Program · U17 Women")

        // Leaving keeps the team and its sessions, and stops scoring against the standards.
        data.sessions.append(TrainingSession(date: Fixtures.day(0), programID: AppData.ndtpProgramID, category: .team, minutes: 120, effort: 7))
        data.setNDTPGroup(nil)
        XCTAssertNil(data.profile.benchmarkGroup)
        XCTAssertNotNil(data.ndtpProgram)
    }

    func testProfilesWithoutAGroupLoadAndSync() throws {
        var data = Fixtures.season()
        data.profile.benchmarkGroup = nil
        let decoded = try AppData.decoder.decode(AppData.self, from: AppData.encoder.encode(data))
        XCTAssertNil(decoded.profile.benchmarkGroup)

        let snapshot = ProfileSnapshot(data)
        XCTAssertNil(snapshot.profile.benchmarkGroup)
        XCTAssertNil(snapshot.appData.profile.benchmarkGroup)
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.profile)) as? [String: Any]
        XCTAssertNil(row?["benchmark_group"], "no group writes a null")

        let json = """
        [{"id": "10000000-0000-4000-8000-000000000001", "first_name": "Sam", "class_year": null, "positions": "", "benchmark_group": null,
          "mental_coach_name": "", "weekly_goal_hours": 12, "season_label": "2026/27", "season_budget": 0, "theme_id": "original"}]
        """
        let rows = try JSONDecoder().decode([ProfileRow].self, from: Data(json.utf8))
        XCTAssertNil(rows.first?.benchmarkGroup)
    }
}
