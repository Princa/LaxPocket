import XCTest
@testable import LaxPocketCore

/// Syncs through a real PostgREST serving the schema in supabase/migrations.
///
/// Skipped unless these are set (CI's "Supabase schema & sync" job sets them up):
///   LAXPOCKET_E2E_REST_URL   e.g. http://127.0.0.1:3000
///   LAXPOCKET_E2E_TOKEN_A    JWT for account A (role "authenticated")
///   LAXPOCKET_E2E_TOKEN_B    JWT for account B
///   LAXPOCKET_E2E_EMAIL_B    account B's email in auth.users
final class CloudSyncIntegrationTests: XCTestCase {
    private var restURL: URL!
    private var tokenA = ""
    private var tokenB = ""
    private var emailB = ""

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["LAXPOCKET_E2E_REST_URL"].flatMap(URL.init(string:)),
              let a = env["LAXPOCKET_E2E_TOKEN_A"], let b = env["LAXPOCKET_E2E_TOKEN_B"], let email = env["LAXPOCKET_E2E_EMAIL_B"] else {
            // CI sets LAXPOCKET_E2E_REQUIRED so a broken setup fails instead of quietly skipping.
            if env["LAXPOCKET_E2E_REQUIRED"] != nil { XCTFail("LAXPOCKET_E2E_* variables are missing") }
            throw XCTSkip("Set LAXPOCKET_E2E_* to run against PostgREST")
        }
        restURL = url
        tokenA = a
        tokenB = b
        emailB = email
    }

    private func sync(_ token: String, pageSize: Int = 1000) async -> CloudSync {
        let config = SupabaseConfig(url: restURL, anonKey: "anon", restURL: restURL)
        let session = AuthSession(accessToken: token, refreshToken: "unused", expiresAt: .distantFuture, userID: UUID(), email: nil)
        let client = SupabaseClient(config: config, session: session)
        await client.setPageSize(pageSize)
        return CloudSync(client: client)
    }

    /// Order-independent comparison of what two sides hold.
    private func assertSame(_ a: ProfileSnapshot?, _ b: ProfileSnapshot?, file: StaticString = #filePath, line: UInt = #line) {
        guard let a, let b else { return XCTFail("missing snapshot", file: file, line: line) }
        XCTAssertEqual(a.profile, b.profile, file: file, line: line)
        XCTAssertEqual(Set(a.programs), Set(b.programs), "programs", file: file, line: line)
        XCTAssertEqual(Set(a.sessions), Set(b.sessions), "sessions", file: file, line: line)
        XCTAssertEqual(Set(a.combineResults), Set(b.combineResults), "combine", file: file, line: line)
        XCTAssertEqual(Set(a.events), Set(b.events), "events", file: file, line: line)
        XCTAssertEqual(Set(a.expenses), Set(b.expenses), "expenses", file: file, line: line)
        XCTAssertEqual(Set(a.docs), Set(b.docs), "docs", file: file, line: line)
        XCTAssertEqual(Set(a.bodyMeasurements), Set(b.bodyMeasurements), "height and weight", file: file, line: line)
        XCTAssertEqual(Set(a.wallballDrills), Set(b.wallballDrills), "wall ball drills", file: file, line: line)
        XCTAssertEqual(Set(a.wallballSessions), Set(b.wallballSessions), "wall ball", file: file, line: line)
    }

    func testTwoDevicesSyncOneAthlete() async throws {
        let season = Fixtures.season(name: "E2E \(UUID().uuidString.prefix(6))")
        // A small page size makes every read span several pages.
        let phone = await sync(tokenA, pageSize: 2)
        let tablet = await sync(tokenA)

        // 1. First upload from the phone.
        var phoneBase = try await phone.sync(local: season, base: nil)
        assertSame(phoneBase, ProfileSnapshot(season))
        let uploaded = try await phone.snapshot(profileID: season.id)
        assertSame(uploaded, ProfileSnapshot(season))
        let visible = try await phone.profiles()
        XCTAssertTrue(visible.contains { $0.id == season.id })

        // 2. The tablet downloads it.
        let downloaded = try await tablet.snapshot(profileID: season.id)
        var tabletBase = try XCTUnwrap(downloaded)
        var tabletData = tabletBase.appData
        assertSame(ProfileSnapshot(tabletData), ProfileSnapshot(season))

        // 3. Both edit, then sync one after the other.
        var phoneData = phoneBase.appData
        phoneData.sessions[0].minutes = 75
        phoneData.expenses.removeAll { $0.title.hasPrefix("Skills coach") }
        phoneData.programs.removeAll { $0.id == "combine" }
        phoneData.events[0].focus[1].outcome = .missed
        phoneData.events[0].stats = nil
        phoneData.events[0].videos = []
        phoneData.combineResults[0].measurements.removeAll { $0.metric == .gripLeft }
        phoneData.events.append(SeasonEvent(kind: .tournament, title: "Winter tournament", team: "Club 2031", date: Fixtures.day(90), endDate: Fixtures.day(91)))
        phoneData.bodyMeasurements[1].heightCm = 160.1
        phoneData.bodyMeasurements.removeAll { $0.id == season.bodyMeasurements[2].id }
        phoneData.wallballSessions[0].sets.removeAll { $0.drillID == "twister" }
        phoneData.wallballSessions[0].sets[0].reps = 60
        phoneData.wallballDrills.removeAll { $0.id == "behind-the-back" }

        tabletData.sessions[2].notes = "From the tablet"
        tabletData.docs.append(MentalDoc(title: "Season goals", url: URL(string: "https://docs.google.com/document/d/xyz")!, folder: .goals,
                                         updatedAt: Fixtures.day(2), updatedBy: "Sam"))
        tabletData.profile.weeklyGoalHours = 14
        tabletData.profile.bodyUnits = .imperial
        tabletData.bodyMeasurements.append(BodyMeasurement(date: Fixtures.day(5, hour: 8), heightCm: 160.3, weightKg: 48.53))
        tabletData.wallballSessions.append(WallballSession(date: Fixtures.day(2, hour: 7), sets: [WallballSet(drillID: "sidearm", hand: .left, reps: 25)]))
        tabletData.wallballSessions.removeAll { $0.id == season.wallballSessions[1].id }

        phoneBase = try await phone.sync(local: phoneData, base: phoneBase)
        tabletBase = try await tablet.sync(local: tabletData, base: tabletBase)
        phoneBase = try await phone.sync(local: phoneBase.appData, base: phoneBase)

        // 4. Both now hold both sets of edits, and so does the cloud.
        assertSame(phoneBase, tabletBase)
        let cloudNow = try await phone.snapshot(profileID: season.id)
        let cloud = try XCTUnwrap(cloudNow)
        assertSame(cloud, phoneBase)
        let final = cloud.appData
        XCTAssertEqual(final.sessions.first { $0.id == season.sessions[0].id }?.minutes, 75)
        XCTAssertEqual(final.sessions.first { $0.id == season.sessions[2].id }?.notes, "From the tablet")
        XCTAssertEqual(final.expenses.count, 1)
        XCTAssertFalse(final.programs.contains { $0.id == "combine" })
        XCTAssertEqual(final.docs.count, 2)
        XCTAssertEqual(final.profile.weeklyGoalHours, 14)
        XCTAssertEqual(final.profile.bodyUnits, .imperial)
        XCTAssertEqual(final.bodyMeasurements.map(\.heightCm), [157.5, 160.1, 160.3])
        XCTAssertEqual(final.bodyMeasurements.last?.weightKg, 48.53)
        XCTAssertTrue(final.events.contains { $0.title == "Winter tournament" })
        XCTAssertEqual(final.wallballSessions.map(\.reps.total), [130, 25])
        XCTAssertEqual(final.wallballSessions[0].sets.map(\.drillID), ["overhand", "overhand", "switch-hands"])
        XCTAssertEqual(final.wallballDrills.map(\.id), ["twister"])
        let game = try XCTUnwrap(final.events.first { $0.id == season.events[0].id })
        XCTAssertNil(game.stats)
        XCTAssertTrue(game.videos.isEmpty)
        XCTAssertEqual(game.focus.map(\.outcome), [.hit, .missed])
        XCTAssertNotNil(game.reflection)
        XCTAssertNil(final.combineResults[0].value(for: .gripLeft))
        XCTAssertEqual(final.combineResults[0].value(for: .gripRight), 285)

        // 5. Nothing left to send.
        let again = ProfileMerge.merge(base: phoneBase, local: ProfileSnapshot(final), remote: cloud)
        XCTAssertTrue(again.changes.isEmpty)

        // 6. Another account can't see it until it's shared, and a viewer can't change it.
        let other = await sync(tokenB)
        let hidden = try await other.snapshot(profileID: season.id)
        XCTAssertNil(hidden)
        try await phone.share(profileID: season.id, email: emailB, role: .viewer)
        let shared = try await other.snapshot(profileID: season.id)
        assertSame(shared, cloud)
        var viewerEdit = final
        viewerEdit.sessions[0].minutes = 5
        do {
            _ = try await other.sync(local: viewerEdit, base: cloud)
            XCTFail("a viewer can't write")
        } catch {
            XCTAssertEqual(error.localizedDescription, "This account can’t change that athlete (view-only access).")
        }
        do {
            try await other.deleteProfile(season.id)
            XCTFail("only the owner can delete")
        } catch {}

        // 7. The owner deletes it from the cloud.
        try await phone.deleteProfile(season.id)
        let gone = try await phone.snapshot(profileID: season.id)
        XCTAssertNil(gone)
    }
}
