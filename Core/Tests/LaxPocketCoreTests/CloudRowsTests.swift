import XCTest
@testable import LaxPocketCore

final class TimestampTests: XCTestCase {
    func testParsesPostgresFormats() {
        let expected: Int64 = 1_790_523_112_925 // 2026-09-27T15:31:52.925Z
        XCTAssertEqual(Timestamp.parse("2026-09-27T15:31:52.925Z"), expected)
        XCTAssertEqual(Timestamp.parse("2026-09-27T15:31:52.925+00:00"), expected)
        XCTAssertEqual(Timestamp.parse("2026-09-27 15:31:52.925+00"), expected)
        XCTAssertEqual(Timestamp.parse("2026-09-27T15:31:52.925209+00:00"), expected)
        XCTAssertEqual(Timestamp.parse("2026-09-27T15:31:52.9256+00:00"), expected + 1, "rounds to the nearest millisecond")
        XCTAssertEqual(Timestamp.parse("2026-09-27T11:31:52.925-04:00"), expected)
        XCTAssertEqual(Timestamp.parse("2026-09-27T21:01:52.925+0530"), expected)
        XCTAssertEqual(Timestamp.parse("2026-09-27T15:31:52"), expected - 925)
        XCTAssertEqual(Timestamp.parse("1970-01-01T00:00:00Z"), 0)
        XCTAssertEqual(Timestamp.parse("1969-12-31T23:59:59.500Z"), -500)
    }

    func testRejectsNonsense() {
        for text in ["", "2026-09-27", "2026-13-01T00:00:00Z", "2026-09-27T25:00:00Z", "2026-09-27T15:31:52.Z", "2026-09-27T15:31:52Zjunk", "yesterday"] {
            XCTAssertNil(Timestamp.parse(text), text)
        }
    }

    func testFormatsAndRoundTrips() throws {
        XCTAssertEqual(Timestamp(milliseconds: 1_790_523_112_925).description, "2026-09-27T15:31:52.925Z")
        XCTAssertEqual(Timestamp(milliseconds: -500).description, "1969-12-31T23:59:59.500Z")
        XCTAssertEqual(Timestamp(milliseconds: 951_782_400_000).description, "2000-02-29T00:00:00.000Z")
        for ms: Int64 in [0, 1, -1, 951_782_400_000, 1_790_523_112_925, 4_102_444_799_999] {
            let stamp = Timestamp(milliseconds: ms)
            XCTAssertEqual(Timestamp.parse(stamp.description), ms)
            let json = try JSONEncoder().encode([stamp])
            XCTAssertEqual(try JSONDecoder().decode([Timestamp].self, from: json), [stamp])
        }
    }

    func testDropsSubMillisecondNoise() {
        let date = Date(timeIntervalSince1970: 1_790_523_112.925_4)
        XCTAssertEqual(Timestamp(date).milliseconds, 1_790_523_112_925)
        XCTAssertEqual(Timestamp(Timestamp(date).date), Timestamp(date))
    }
}

final class CloudRowsTests: XCTestCase {
    func testSnapshotRoundTripsAppData() throws {
        let data = Fixtures.season()
        let snapshot = ProfileSnapshot(data)
        XCTAssertEqual(snapshot.profile.id, data.id)
        XCTAssertEqual(snapshot.programs.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(snapshot.events.first?.focus.map(\.position), [0, 1])

        let rebuilt = snapshot.appData
        XCTAssertEqual(ProfileSnapshot(rebuilt), snapshot, "rows → app data → rows changes nothing")
        XCTAssertEqual(rebuilt.profile, data.profile)
        XCTAssertEqual(rebuilt.themeID, data.themeID)
        XCTAssertEqual(rebuilt.seasonBudget, data.seasonBudget)
        XCTAssertEqual(rebuilt.programs, data.programs)
        XCTAssertEqual(rebuilt.sessions.map(\.id), data.sessions.map(\.id))
        XCTAssertEqual(rebuilt.events.first { $0.kind == .game }?.stats, data.events.first?.stats)
        XCTAssertEqual(rebuilt.events.first { $0.kind == .game }?.reflection?.coachFeedback, "Stick up on D")
        XCTAssertEqual(rebuilt.events.first { $0.kind == .showcase }?.checklist.map(\.title), ["Registration", "Flights"])
        XCTAssertEqual(rebuilt.combineResults.first?.value(for: .sprint10m), 1.965)
        XCTAssertEqual(rebuilt.docs.first?.url, data.docs.first?.url)
        XCTAssertEqual(rebuilt.expenses.map(\.amount).sorted(), [320.5, 1850])
        XCTAssertEqual(rebuilt.bodyMeasurements, data.bodyMeasurements)
        XCTAssertEqual(rebuilt.profile.bodyUnits, .metric)
        XCTAssertEqual(rebuilt.wallballDrills, data.wallballDrills)
        XCTAssertEqual(rebuilt.wallballSessions, data.wallballSessions)
        XCTAssertEqual(rebuilt.expenses.sorted { $0.date < $1.date }, data.expenses.sorted { $0.date < $1.date })
        XCTAssertEqual(rebuilt.seasonBudgets, data.seasonBudgets)
        XCTAssertEqual(rebuilt.programBudgets, data.programBudgets)
        XCTAssertEqual(rebuilt.trips, data.trips)

        let json = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(ProfileSnapshot.self, from: json), snapshot)
    }

    func testSameRowsIgnoresOrder() {
        let data = Fixtures.season()
        var shuffled = data
        shuffled.sessions.reverse()
        shuffled.docs.reverse()
        shuffled.bodyMeasurements.reverse()
        XCTAssertTrue(ProfileSnapshot(shuffled).hasSameRows(as: ProfileSnapshot(data)))
        shuffled.sessions[0].notes = "changed"
        XCTAssertFalse(ProfileSnapshot(shuffled).hasSameRows(as: ProfileSnapshot(data)))
        shuffled = data
        shuffled.bodyMeasurements[0].weightKg = 50
        XCTAssertFalse(ProfileSnapshot(shuffled).hasSameRows(as: ProfileSnapshot(data)))
        shuffled = data
        shuffled.wallballSessions.reverse()
        XCTAssertTrue(ProfileSnapshot(shuffled).hasSameRows(as: ProfileSnapshot(data)))
        shuffled.wallballSessions[0].sets[0].reps = 1
        XCTAssertFalse(ProfileSnapshot(shuffled).hasSameRows(as: ProfileSnapshot(data)))
    }

    func testValuesAreNormalizedToWhatTheDatabaseStores() {
        var data = Fixtures.season()
        data.profile.classYear = 31
        data.profile.weeklyGoalHours = 12.25
        data.seasonBudget = 999.999
        data.expenses[0].amount = 10.005
        data.programBudgets[0].amount = 0.001
        data.combineResults[0].measurements.append(CombineMeasurement(metric: .gripLeft, value: 300))
        let snapshot = ProfileSnapshot(data)
        XCTAssertNil(snapshot.profile.classYear, "the column only takes graduation years")
        XCTAssertEqual(snapshot.profile.weeklyGoalHours, 12.3)
        XCTAssertEqual(snapshot.profile.seasonBudget, 1000)
        XCTAssertEqual(snapshot.expenses[0].amount, 10.01)
        XCTAssertEqual(snapshot.seasonBudgets.map(\.amount), [1000])
        XCTAssertEqual(snapshot.programBudgets.count, 2, "a budget that rounds to nothing has no row")
        let grips = snapshot.combineResults[0].measurements.filter { $0.metric == .gripLeft }
        XCTAssertEqual(grips.map(\.value), [300], "one value per metric; the last one wins")
    }

    func testBodyMeasurementsAreRoundedAndChecked() {
        var data = Fixtures.season()
        data.bodyMeasurements = [
            BodyMeasurement(date: Fixtures.day(0), heightCm: 162.56, weightKg: 50.802_345),
            BodyMeasurement(date: Fixtures.day(1), heightCm: 5.4, weightKg: 49),
            BodyMeasurement(date: Fixtures.day(2), heightCm: 400),
            BodyMeasurement(date: Fixtures.day(3))
        ]
        let rows = ProfileSnapshot(data).bodyMeasurements
        XCTAssertEqual(rows.count, 2, "a measurement with nothing the database accepts has no row")
        XCTAssertEqual(rows[0].heightCm, 162.6)
        XCTAssertEqual(rows[0].weightKg, 50.8)
        XCTAssertNil(rows[1].heightCm, "a height in feet typed as centimetres is left out")
        XCTAssertEqual(rows[1].weightKg, 49)
    }

    func testWallballRowsAreKeptInRange() {
        var data = Fixtures.season()
        data.wallballDrills = [WallballDrill(id: "mine", name: "  ", defaultReps: 0)]
        data.wallballSessions = [
            WallballSession(date: Fixtures.day(0), sets: [
                WallballSet(drillID: "overhand", hand: .right, reps: 30), WallballSet(drillID: "sidearm", hand: .left, reps: 0),
                WallballSet(drillID: "overhand", hand: .right, reps: 20), WallballSet(drillID: "overhand", hand: .left, reps: 9_000)
            ], minutes: 0, challengeSeconds: 1)
        ]
        let snapshot = ProfileSnapshot(data)
        XCTAssertEqual(snapshot.wallballDrills[0].name, "Drill", "a blank name would fail the database check")
        XCTAssertEqual(snapshot.wallballDrills[0].defaultReps, 1)
        let bundle = snapshot.wallballSessions[0]
        XCTAssertNil(bundle.session.minutes)
        XCTAssertNil(bundle.session.challengeSeconds)
        XCTAssertEqual(bundle.sets.map(\.reps), [50, 5000], "repeats of a drill and hand add up, empty sets are dropped, reps are capped")
        XCTAssertEqual(bundle.sets.map(\.position), [0, 1])
    }

    func testBudgetRowsOnlyPointAtProgramsThatExist() {
        var data = Fixtures.season()
        data.programs.removeAll { $0.id == "club" }
        data.programs[0].firstSeason = 2028
        data.programs[0].lastSeason = 2026
        data.programs[1].firstSeason = 1999
        data.expenses[1].season = 3000
        let snapshot = ProfileSnapshot(data)
        XCTAssertNil(snapshot.expenses[0].programID, "a link to a deleted program would fail the foreign key")
        XCTAssertEqual(snapshot.programBudgets.map(\.programID), ["skills-coach"])
        XCTAssertEqual(snapshot.programs[0].firstSeason, 2026, "a range typed backwards is turned around")
        XCTAssertEqual(snapshot.programs[0].lastSeason, 2028)
        XCTAssertNil(snapshot.programs[1].firstSeason)
        XCTAssertEqual(snapshot.expenses[1].season, 2026, "a season the database won't take falls back to the season of the date")
    }

    /// Rows from before budgets per season: programs and expenses without seasons, and no budget tables.
    func testReadsRowsFromBeforeBudgetsPerSeason() throws {
        let json = """
        [{"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "profile_id": "10000000-0000-4000-8000-000000000001", "spent_at": "2027-03-01T12:00:00+00:00",
          "title": "Stick", "category": "equipment", "amount": 250, "note": "", "program_id": null, "season": null}]
        """
        let expense = try XCTUnwrap(JSONDecoder().decode([ExpenseRow].self, from: Data(json.utf8)).first)
        XCTAssertEqual(expense.season, 2026)
        XCTAssertNil(expense.programID)

        let snapshot = ProfileSnapshot(Fixtures.season())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(snapshot)) as? [String: Any])
        object["seasonBudgets"] = nil
        object["programBudgets"] = nil
        object["expenses"] = (object["expenses"] as? [[String: Any]])?.map { row in
            var row = row
            row["season"] = nil
            row["program_id"] = nil
            return row
        }
        let old = try AppData.decoder.decode(ProfileSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.seasonBudgets.isEmpty)
        XCTAssertEqual(old.expenses.map(\.season), [2026, 2026])
    }

    /// Sync records written before height and weight tracking still load, so the next sync has its base.
    func testReadsSyncRecordsFromBeforeHeightAndWeight() throws {
        let snapshot = ProfileSnapshot(Fixtures.season())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(snapshot)) as? [String: Any])
        object["bodyMeasurements"] = nil
        object["wallballDrills"] = nil
        object["wallballSessions"] = nil
        var profile = try XCTUnwrap(object["profile"] as? [String: Any])
        profile["body_units"] = nil
        object["profile"] = profile

        let old = try AppData.decoder.decode(ProfileSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.bodyMeasurements.isEmpty)
        XCTAssertTrue(old.wallballSessions.isEmpty)
        XCTAssertEqual(old.profile.bodyUnits, .imperial)
        XCTAssertEqual(old.sessions, snapshot.sessions)
    }

    /// Every row encodes exactly the columns it declares, with snake_case names.
    func testRowsEncodeTheirColumns() throws {
        let snapshot = ProfileSnapshot(Fixtures.season())
        let game = try XCTUnwrap(snapshot.events.first { $0.stats != nil })
        func keys<Row: CloudRow>(_ row: Row) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
            return Set(object?.keys.map { $0 } ?? [])
        }
        func check<Row: CloudRow>(_ row: Row, file: StaticString = #filePath, line: UInt = #line) throws {
            let encoded = try keys(row)
            XCTAssertTrue(encoded.isSubset(of: Set(Row.columns)), "\(Row.table): \(encoded.subtracting(Row.columns))", file: file, line: line)
            XCTAssertTrue(Set(Row.conflictColumns).isSubset(of: encoded), "\(Row.table) conflict columns", file: file, line: line)
        }
        try check(snapshot.profile)
        XCTAssertEqual(try keys(snapshot.profile), Set(ProfileRow.columns).subtracting(["athlete_id", "shoots"]),
                       "a lacrosse athlete's first profile has neither")
        var hockey = Fixtures.season().addingSport(.hockey)
        hockey.profile.shoots = .left
        XCTAssertEqual(try keys(ProfileRow(hockey)), Set(ProfileRow.columns).subtracting(["benchmark_group"]), "hockey has no NDTP group")
        try check(snapshot.programs[0])
        try check(snapshot.sessions[0])
        try check(snapshot.combineResults[0].result)
        try check(snapshot.combineResults[0].measurements[0])
        try check(game.event)
        XCTAssertEqual(try keys(game.event), Set(EventRow.columns).subtracting(["ends_at"]), "nil values are left out and written as null")
        try check(try XCTUnwrap(game.stats))
        try check(try XCTUnwrap(game.reflection))
        try check(game.focus[0])
        try check(game.videos[0])
        try check(try XCTUnwrap(snapshot.events.first { !$0.checklist.isEmpty }).checklist[0])
        try check(snapshot.expenses[0])
        XCTAssertEqual(try keys(snapshot.expenses[0]), Set(ExpenseRow.columns).subtracting(["trip_id", "original_amount"]))
        XCTAssertEqual(try keys(snapshot.expenses[1]), Set(ExpenseRow.columns).subtracting(["program_id", "trip_id", "original_amount"]),
                       "no program writes a null link")
        try check(snapshot.trips[0])
        XCTAssertEqual(try keys(snapshot.trips[0]), Set(TripRow.columns).subtracting(["hotel_check_out"]))
        try check(snapshot.seasonBudgets[0])
        try check(snapshot.programBudgets[0])
        XCTAssertEqual(try keys(snapshot.programs[0]), Set(ProgramRow.columns))
        try check(snapshot.docs[0])
        try check(snapshot.bodyMeasurements[0])
        XCTAssertEqual(try keys(snapshot.bodyMeasurements[0]), Set(BodyMeasurementRow.columns))
        XCTAssertEqual(try keys(snapshot.bodyMeasurements[2]), Set(BodyMeasurementRow.columns).subtracting(["height_cm"]),
                       "a weigh-in without a height writes a null height")
        try check(snapshot.wallballDrills[0])
        try check(snapshot.wallballSessions[0].sets[0])
        XCTAssertEqual(try keys(snapshot.wallballSessions[0].session), Set(WallballSessionRow.columns).subtracting(["challenge_seconds"]))
        XCTAssertEqual(try keys(snapshot.wallballSessions[1].session), Set(WallballSessionRow.columns).subtracting(["minutes"]))
    }

    func testDecodesPostgRESTRows() throws {
        let json = """
        [{"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "profile_id": "10000000-0000-4000-8000-000000000001", "kind": "game",
          "title": "vs Rivals", "team": "Club", "opponent": null, "starts_at": "2026-09-26T12:00:00+00:00", "ends_at": null,
          "date_is_tentative": false, "location": "", "our_score": 11, "their_score": 7,
          "created_at": "2026-09-27T15:31:52.925209+00:00", "updated_at": "2026-09-27T15:31:52.925209+00:00"}]
        """
        let rows = try JSONDecoder().decode([EventRow].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.startsAt.description, "2026-09-26T12:00:00.000Z")
        XCTAssertNil(rows.first?.opponent)
        XCTAssertEqual(rows.first?.ourScore, 11)

        let body = """
        [{"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3302", "profile_id": "10000000-0000-4000-8000-000000000001",
          "measured_at": "2026-09-28T12:00:00+00:00", "height_cm": 162.6, "weight_kg": null, "note": "",
          "created_at": "2026-09-28T12:00:00.1+00:00", "updated_at": "2026-09-28T12:00:00.1+00:00"}]
        """
        let bodyRows = try JSONDecoder().decode([BodyMeasurementRow].self, from: Data(body.utf8))
        XCTAssertEqual(bodyRows.first?.heightCm, 162.6)
        XCTAssertNil(bodyRows.first?.weightKg)
    }

    func testSupabaseConfigFromPlistValues() {
        XCTAssertNil(SupabaseConfig(values: [:]))
        XCTAssertNil(SupabaseConfig(values: ["SupabaseURL": "https://YOUR-PROJECT.supabase.co", "SupabaseAnonKey": "abc"]))
        XCTAssertNil(SupabaseConfig(values: ["SupabaseURL": "https://abc.supabase.co", "SupabaseAnonKey": " "]))
        let config = SupabaseConfig(values: ["SupabaseURL": "https://abc.supabase.co", "SupabaseAnonKey": "sb_publishable_123"])
        XCTAssertEqual(config?.restURL.absoluteString, "https://abc.supabase.co/rest/v1")
        XCTAssertEqual(config?.authURL.absoluteString, "https://abc.supabase.co/auth/v1")
    }
}
