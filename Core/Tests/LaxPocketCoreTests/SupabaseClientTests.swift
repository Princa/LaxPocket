import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import LaxPocketCore

/// Records requests and answers them from a script.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body = "[]"
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = record(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    private func record(_ request: URLRequest) -> Reply {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return replies.isEmpty ? Reply() : replies.removeFirst()
    }

    func query(_ index: Int) -> [String: String] {
        let items = URLComponents(url: requests[index].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    func json(_ index: Int) -> Any? {
        requests[index].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }
}

final class SupabaseClientTests: XCTestCase {
    private let config = SupabaseConfig(url: URL(string: "https://abc.supabase.co")!, anonKey: "anon-key")
    private let userID = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(expiresIn seconds: TimeInterval = 3600) -> AuthSession {
        AuthSession(accessToken: "access", refreshToken: "refresh", expiresAt: now.addingTimeInterval(seconds), userID: userID, email: "a@example.com")
    }

    private var tokenJSON: String {
        """
        {"access_token": "new-access", "token_type": "bearer", "expires_in": 3600, "expires_at": 1790003600,
         "refresh_token": "new-refresh", "user": {"id": "00000000-0000-4000-8000-00000000000a", "email": "a@example.com"}}
        """
    }

    private func client(_ transport: FakeTransport, session: AuthSession? = nil) -> SupabaseClient {
        let fixedNow = now
        return SupabaseClient(config: config, session: session, transport: transport, now: { fixedNow })
    }

    func testSignIn() async throws {
        let transport = FakeTransport([.init(body: tokenJSON)])
        let client = client(transport)
        let session = try await client.signIn(email: "a@example.com", password: "secret")
        XCTAssertEqual(session.accessToken, "new-access")
        XCTAssertEqual(session.userID, userID)
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 1_790_003_600))

        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/auth/v1/token?grant_type=password")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(transport.json(0) as? [String: String], ["email": "a@example.com", "password": "secret"])
        let stored = await client.session
        XCTAssertEqual(stored, session)
    }

    func testSignInErrorMessage() async {
        let transport = FakeTransport([.init(status: 400, body: #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#)])
        do {
            _ = try await client(transport).signIn(email: "a@example.com", password: "wrong")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid login credentials")
        }
    }

    func testSignUpNeedingEmailConfirmation() async throws {
        let transport = FakeTransport([.init(body: #"{"id": "00000000-0000-4000-8000-00000000000a", "email": "a@example.com", "confirmation_sent_at": "2026-09-27T10:00:00Z"}"#)])
        let result = try await client(transport).signUp(email: "a@example.com", password: "secret")
        XCTAssertEqual(result, .confirmEmail)
        XCTAssertEqual(transport.requests[0].url?.path, "/auth/v1/signup")
    }

    func testSignUpSendsTheRedirect() async throws {
        let transport = FakeTransport([.init(body: #"{"id": "00000000-0000-4000-8000-00000000000a", "email": "a@example.com"}"#)])
        _ = try await client(transport).signUp(email: "a@example.com", password: "secret", redirectTo: URL(string: "laxpocket://auth-callback")!)
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://abc.supabase.co/auth/v1/signup?redirect_to=laxpocket://auth-callback")
    }

    func testResendConfirmation() async throws {
        let transport = FakeTransport([.init(body: "{}")])
        try await client(transport).resendConfirmation(email: "a@example.com", redirectTo: URL(string: "laxpocket://auth-callback")!)
        XCTAssertEqual(transport.requests[0].url?.path, "/auth/v1/resend")
        XCTAssertEqual(transport.query(0), ["redirect_to": "laxpocket://auth-callback"])
        XCTAssertEqual(transport.json(0) as? [String: String], ["type": "signup", "email": "a@example.com"])
    }

    func testSignInFromConfirmationLink() async throws {
        let transport = FakeTransport([.init(body: #"{"id": "00000000-0000-4000-8000-00000000000a", "email": "a@example.com"}"#)])
        let client = client(transport)
        let link = URL(string: "laxpocket://auth-callback#access_token=new-access&expires_at=1790003600&expires_in=3600&refresh_token=new-refresh&token_type=bearer&type=signup")!
        let session = try await client.signIn(fromRedirect: link)
        XCTAssertEqual(session, AuthSession(accessToken: "new-access", refreshToken: "new-refresh",
                                            expiresAt: Date(timeIntervalSince1970: 1_790_003_600), userID: userID, email: "a@example.com"))
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://abc.supabase.co/auth/v1/user")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        let stored = await client.session
        XCTAssertEqual(stored, session)
    }

    func testExpiredConfirmationLink() async {
        let transport = FakeTransport([])
        let link = URL(string: "laxpocket://auth-callback#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired")!
        do {
            _ = try await client(transport).signIn(fromRedirect: link)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CloudError, .server(status: 403, code: "otp_expired", message: "Email link is invalid or has expired"))
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSelectFollowsPages() async throws {
        let transport = FakeTransport([
            .init(body: #"[{"n": 1}, {"n": 2}]"#, headers: ["Content-Range": "0-1/3"]),
            .init(body: #"[{"n": 3}]"#, headers: ["Content-Range": "2-2/3"])
        ])
        struct Row: Decodable, Equatable { var n: Int }
        let client = client(transport, session: session())
        await client.setPageSize(2)
        let rows = try await client.select("expenses", filters: [URLQueryItem(name: "profile_id", value: "eq.abc")], order: "id", as: Row.self)
        XCTAssertEqual(rows, [Row(n: 1), Row(n: 2), Row(n: 3)])
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.path, "/rest/v1/expenses")
        XCTAssertEqual(transport.query(0), ["select": "*", "profile_id": "eq.abc", "order": "id", "limit": "2", "offset": "0"])
        XCTAssertEqual(transport.query(1)["offset"], "2")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Prefer"), "count=exact")
    }

    /// If the server caps rows below our page size, keep reading until it runs out.
    func testSelectWithoutTotalStopsOnEmptyPage() async throws {
        let transport = FakeTransport([.init(body: #"[{"n": 1}]"#), .init(body: "[]")])
        struct Row: Decodable { var n: Int }
        let rows = try await client(transport, session: session()).select("expenses", order: "id", as: Row.self)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testUpsertSendsColumnsAndConflictTarget() async throws {
        let transport = FakeTransport([.init(status: 201, body: "")])
        let snapshot = ProfileSnapshot(Fixtures.season())
        try await client(transport, session: session()).upsert(snapshot.programs)

        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/rest/v1/programs")
        XCTAssertEqual(transport.query(0)["on_conflict"], "profile_id,id")
        XCTAssertEqual(transport.query(0)["columns"], ProgramRow.columns.joined(separator: ","))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let body = transport.json(0) as? [[String: Any]]
        XCTAssertEqual(body?.count, 4)
        XCTAssertEqual(body?.first?["program_group"] as? String, "teams")
        XCTAssertNil(body?.last?["session_category"] as? String)
    }

    func testDeleteQuotesValues() async throws {
        let transport = FakeTransport([.init(body: #"[{"id": "a"}, {"id": "b"}]"#)])
        let count = try await client(transport, session: session())
            .delete("programs", where: "id", in: ["team-ontario", #"odd"name"#], filters: [URLQueryItem(name: "profile_id", value: "eq.p1")])
        XCTAssertEqual(count, 2)
        XCTAssertEqual(transport.requests[0].httpMethod, "DELETE")
        XCTAssertEqual(transport.query(0)["id"], #"in.("team-ontario","odd\"name")"#)
        XCTAssertEqual(transport.query(0)["profile_id"], "eq.p1")
    }

    func testNothingToWriteSendsNothing() async throws {
        let transport = FakeTransport([])
        let client = client(transport, session: session())
        try await client.upsert([ExpenseRow]())
        try await client.delete("expenses", where: "id", in: [])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPlusSignsAreEncoded() {
        let url = SupabaseClient.url(URL(string: "https://x.co/rest/v1/t")!, [URLQueryItem(name: "at", value: "gte.2026-09-27T10:00:00+00:00")])
        XCTAssertEqual(url.absoluteString, "https://x.co/rest/v1/t?at=gte.2026-09-27T10:00:00%2B00:00")
    }

    func testRefreshesAnExpiringToken() async throws {
        let transport = FakeTransport([.init(body: tokenJSON), .init(body: "[]")])
        let client = client(transport, session: session(expiresIn: 30))
        _ = try await client.select("expenses", order: "id", as: ExpenseRow.self)
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://abc.supabase.co/auth/v1/token?grant_type=refresh_token")
        XCTAssertEqual(transport.json(0) as? [String: String], ["refresh_token": "refresh"])
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        let stored = await client.session
        XCTAssertEqual(stored?.refreshToken, "new-refresh")
    }

    func testRetriesOnceAfter401() async throws {
        let transport = FakeTransport([
            .init(status: 401, body: #"{"code":"PGRST301","message":"JWT expired"}"#),
            .init(body: tokenJSON),
            .init(body: "[]")
        ])
        _ = try await client(transport, session: session()).select("expenses", order: "id", as: ExpenseRow.self)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    }

    func testRevokedRefreshTokenSignsOut() async {
        let transport = FakeTransport([.init(status: 400, body: #"{"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"#)])
        let client = client(transport, session: session(expiresIn: 0))
        do {
            _ = try await client.select("expenses", order: "id", as: ExpenseRow.self)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Signed out. Please sign in again.")
        }
        let stored = await client.session
        XCTAssertNil(stored)
    }

    func testNotSignedIn() async {
        do {
            _ = try await client(FakeTransport([])).select("expenses", order: "id", as: ExpenseRow.self)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CloudError, .notSignedIn)
        }
    }

    func testRowLevelSecurityErrorIsReadable() async {
        let transport = FakeTransport([.init(status: 403, body: #"{"code":"42501","message":"new row violates row-level security policy for table \"programs\""}"#)])
        do {
            try await client(transport, session: session()).upsert(ProfileSnapshot(Fixtures.season()).programs)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "This account can’t change that athlete (view-only access).")
        }
    }
}

extension SupabaseClient {
    func setPageSize(_ size: Int) {
        pageSize = size
    }
}
