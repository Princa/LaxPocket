import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the Supabase project is. The anon (publishable) key is meant to ship in apps;
/// row-level security decides what each signed-in account can see.
public struct SupabaseConfig: Equatable, Sendable {
    public var url: URL
    public var anonKey: String
    /// Defaults to `<url>/rest/v1` and `<url>/auth/v1`; override to point at a bare PostgREST in tests.
    public var restURL: URL
    public var authURL: URL

    public init(url: URL, anonKey: String, restURL: URL? = nil, authURL: URL? = nil) {
        self.url = url
        self.anonKey = anonKey
        self.restURL = restURL ?? url.appendingPathComponent("rest/v1")
        self.authURL = authURL ?? url.appendingPathComponent("auth/v1")
    }

    /// Reads `SupabaseURL` and `SupabaseAnonKey` (e.g. from Supabase.plist). Nil when either is missing or still a placeholder.
    public init?(values: [String: Any]) {
        guard let urlText = (values["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = (values["SupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty, !key.contains("YOUR"),
              let url = URL(string: urlText), let scheme = url.scheme, scheme.hasPrefix("http"), url.host != nil,
              !urlText.contains("YOUR") else { return nil }
        self.init(url: url, anonKey: key)
    }
}

/// A signed-in Supabase account.
public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: UUID
    public var email: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: UUID, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }
}

public enum CloudError: Error, Equatable, LocalizedError, Sendable {
    case notSignedIn
    case invalidResponse
    /// The server answered with an error status; `message` is its explanation.
    case server(status: Int, code: String?, message: String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to sync."
        case .invalidResponse: return "The server sent something unexpected."
        case .server(let status, let code, let message):
            if code == "42501" {
                // LaxPocket's own functions explain themselves; row-level security's messages don't.
                if !message.isEmpty, !message.hasPrefix("new row violates"), !message.hasPrefix("permission denied") { return message }
                return "This account can’t change that athlete (view-only access)."
            }
            if status == 401 { return "Signed out. Please sign in again." }
            return message.isEmpty ? "Server error \(status)." : message
        }
    }
}

/// Sends HTTP requests. Swapped for a fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: CloudError.invalidResponse)
                }
            }.resume()
        }
    }
}

/// A small client for the two Supabase services LaxPocket uses: Auth (email + password) and the
/// PostgREST data API. Refreshes the access token when it is about to expire.
public actor SupabaseClient {
    public let config: SupabaseConfig
    public private(set) var session: AuthSession?
    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    private let onSessionChange: @Sendable (AuthSession?) -> Void
    private var refreshTask: Task<AuthSession, Error>?

    /// Rows per request when reading and writing.
    public var pageSize = 1000

    public init(config: SupabaseConfig, session: AuthSession? = nil, transport: HTTPTransport = URLSessionTransport(),
                now: @escaping @Sendable () -> Date = { Date() },
                onSessionChange: @escaping @Sendable (AuthSession?) -> Void = { _ in }) {
        self.config = config
        self.session = session
        self.transport = transport
        self.now = now
        self.onSessionChange = onSessionChange
    }

    // MARK: - Auth

    public enum SignUpResult: Equatable, Sendable {
        case signedIn(AuthSession)
        /// The project asks new accounts to confirm their email before signing in.
        case confirmEmail
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let data = try await authRequest("token", query: [URLQueryItem(name: "grant_type", value: "password")], body: body)
        let newSession = try decodeSession(data)
        store(newSession)
        return newSession
    }

    /// `redirectTo` is where the confirmation email's link lands once the email is confirmed. Supabase
    /// only uses it if it's listed under Authentication → URL Configuration → Redirect URLs, and falls
    /// back to the project's Site URL otherwise.
    public func signUp(email: String, password: String, redirectTo: URL? = nil) async throws -> SignUpResult {
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let data = try await authRequest("signup", query: SupabaseClient.redirectQuery(redirectTo), body: body)
        if let newSession = try? decodeSession(data) {
            store(newSession)
            return .signedIn(newSession)
        }
        return .confirmEmail
    }

    /// Sends the confirmation email again, for when the first link expired or got lost.
    public func resendConfirmation(email: String, redirectTo: URL? = nil) async throws {
        let body = try JSONEncoder().encode(["type": "signup", "email": email])
        _ = try await authRequest("resend", query: SupabaseClient.redirectQuery(redirectTo), body: body)
    }

    /// Signs in from the link in a confirmation email. Supabase confirms the email, then opens the
    /// redirect URL with the new session in its fragment (`#access_token=…&refresh_token=…&expires_in=…`),
    /// or with an error (`#error_code=otp_expired&error_description=…`) when the link was already used
    /// or has expired.
    public func signIn(fromRedirect url: URL) async throws -> AuthSession {
        let params = SupabaseClient.redirectParameters(url)
        if let message = params["error_description"] ?? params["error"] {
            throw CloudError.server(status: 403, code: params["error_code"], message: message)
        }
        guard let accessToken = params["access_token"], let refreshToken = params["refresh_token"] else {
            throw CloudError.invalidResponse
        }
        // The fragment doesn't say which account it is, so ask; that also checks the token is genuine.
        var request = URLRequest(url: config.authURL.appendingPathComponent("user"))
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        try SupabaseClient.check(response, data)
        let user = try JSONDecoder().decode(TokenResponse.User.self, from: data)
        let expiresAt = params["expires_at"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            ?? now().addingTimeInterval(params["expires_in"].flatMap(Double.init) ?? 3600)
        let newSession = AuthSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt,
                                     userID: user.id, email: user.email)
        store(newSession)
        return newSession
    }

    /// Ends the session on the server (best effort) and forgets it here.
    public func signOut() async {
        if let session {
            var request = URLRequest(url: config.authURL.appendingPathComponent("logout"))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await transport.send(request)
        }
        refreshTask?.cancel()
        refreshTask = nil
        store(nil)
    }

    /// The current session, refreshed first if it expires within a minute.
    public func validSession() async throws -> AuthSession {
        guard let session else { throw CloudError.notSignedIn }
        if session.expiresAt.timeIntervalSince(now()) > 60 { return session }
        return try await refresh()
    }

    /// Swaps the refresh token for a new session. Concurrent callers share one request, because
    /// refresh tokens are single-use.
    @discardableResult
    public func refresh() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let current = session else { throw CloudError.notSignedIn }
        let task = Task { [config, transport] () throws -> AuthSession in
            var request = URLRequest(url: SupabaseClient.url(config.authURL.appendingPathComponent("token"),
                                                             [URLQueryItem(name: "grant_type", value: "refresh_token")]))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": current.refreshToken])
            let (data, response) = try await transport.send(request)
            try SupabaseClient.check(response, data)
            return try SupabaseClient.decodeSession(data, now: Date())
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let newSession = try await task.value
            store(newSession)
            return newSession
        } catch let CloudError.server(status, code, message) where (400..<500).contains(status) {
            // The refresh token was revoked or already used: the user has to sign in again.
            store(nil)
            throw CloudError.server(status: 401, code: code, message: message)
        }
    }

    private func store(_ newSession: AuthSession?) {
        session = newSession
        onSessionChange(newSession)
    }

    private func authRequest(_ path: String, query: [URLQueryItem] = [], body: Data) async throws -> Data {
        var request = URLRequest(url: SupabaseClient.url(config.authURL.appendingPathComponent(path), query))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await transport.send(request)
        try SupabaseClient.check(response, data)
        return data
    }

    private func decodeSession(_ data: Data) throws -> AuthSession {
        try SupabaseClient.decodeSession(data, now: now())
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            var id: UUID
            var email: String?
        }
        var access_token: String
        var refresh_token: String
        var expires_in: Double?
        var expires_at: Double?
        var user: User
    }

    static func decodeSession(_ data: Data, now: Date) throws -> AuthSession {
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = token.expires_at.map { Date(timeIntervalSince1970: $0) }
            ?? now.addingTimeInterval(token.expires_in ?? 3600)
        return AuthSession(accessToken: token.access_token, refreshToken: token.refresh_token, expiresAt: expiresAt,
                           userID: token.user.id, email: token.user.email)
    }

    // MARK: - Data API

    /// Every row matching the filters, following pages until the server has none left.
    public func select<Row: Decodable>(_ table: String, filters: [URLQueryItem] = [], order: String, as type: Row.Type = Row.self) async throws -> [Row] {
        var all: [Row] = []
        var offset = 0
        while true {
            let query = [URLQueryItem(name: "select", value: "*")] + filters + [
                URLQueryItem(name: "order", value: order),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            let (data, response) = try await rest("GET", table, query: query, prefer: "count=exact")
            let page = try SupabaseClient.decoder.decode([Row].self, from: data)
            all += page
            offset += page.count
            // Content-Range is "0-999/2345"; stop at the total, or on an empty page if there's no total.
            let total = (response.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last).flatMap { Int($0) }
            if page.isEmpty || (total.map { offset >= $0 } ?? false) { return all }
        }
    }

    /// Inserts rows, or updates the ones that already exist.
    public func upsert<Row: CloudRow>(_ rows: [Row]) async throws {
        guard !rows.isEmpty else { return }
        for start in stride(from: 0, to: rows.count, by: pageSize) {
            let chunk = Array(rows[start..<min(start + pageSize, rows.count)])
            let query = [
                URLQueryItem(name: "on_conflict", value: Row.conflictColumns.joined(separator: ",")),
                // Keys missing from a row (nil values) are written as null.
                URLQueryItem(name: "columns", value: Row.columns.joined(separator: ","))
            ]
            _ = try await rest("POST", Row.table, query: query, body: try SupabaseClient.encoder.encode(chunk),
                               prefer: "resolution=merge-duplicates,return=minimal")
        }
    }

    /// Deletes rows where `column` is one of `values`, plus any extra filters. Returns how many were deleted.
    @discardableResult
    public func delete(_ table: String, where column: String, in values: [String], filters: [URLQueryItem] = []) async throws -> Int {
        var deleted = 0
        for start in stride(from: 0, to: values.count, by: 100) {
            let chunk = values[start..<min(start + 100, values.count)]
            let list = chunk.map(SupabaseClient.quoted).joined(separator: ",")
            let query = filters + [URLQueryItem(name: column, value: "in.(\(list))")]
            let (data, _) = try await rest("DELETE", table, query: query, prefer: "return=representation")
            deleted += (try? JSONSerialization.jsonObject(with: data) as? [Any])?.count ?? 0
        }
        return deleted
    }

    /// Calls a Postgres function exposed through the API.
    public func rpc(_ function: String, params: [String: String]) async throws -> Data {
        try await rpc(function, encoded: params)
    }

    /// Calls a Postgres function with parameters that aren't all text (booleans, say).
    public func rpc<Params: Encodable & Sendable>(_ function: String, encoded params: Params) async throws -> Data {
        let (data, _) = try await rest("POST", "rpc/\(function)", body: try JSONEncoder().encode(params))
        return data
    }

    private func rest(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, prefer: String? = nil,
                      retrying: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let session = try await validSession()
        var request = URLRequest(url: SupabaseClient.url(config.restURL.appendingPathComponent(path), query))
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let (data, response) = try await transport.send(request)
        if response.statusCode == 401 && retrying {
            // The token expired early or was revoked; refresh once and try again.
            try await refresh()
            return try await rest(method, path, query: query, body: body, prefer: prefer, retrying: false)
        }
        try SupabaseClient.check(response, data)
        return (data, response)
    }

    // MARK: - Helpers

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func url(_ base: URL, _ query: [URLQueryItem]) -> URL {
        guard !query.isEmpty, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        components.queryItems = query
        // URLComponents leaves "+" alone, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? base
    }

    static func redirectQuery(_ redirectTo: URL?) -> [URLQueryItem] {
        redirectTo.map { [URLQueryItem(name: "redirect_to", value: $0.absoluteString)] } ?? []
    }

    /// The `key=value` pairs in a redirect URL's query and fragment; the fragment wins.
    static func redirectParameters(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var result: [String: String] = [:]
        for encoded in [components.percentEncodedQuery, components.percentEncodedFragment] {
            guard let encoded else { continue }
            var form = URLComponents()
            // Form encoding writes spaces as "+" ("Email+link+is+invalid"); a real plus arrives as %2B.
            form.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%20")
            for item in form.queryItems ?? [] { result[item.name] = item.value ?? "" }
        }
        return result
    }

    /// A value for a PostgREST `in.(…)` list: double-quoted, with quotes and backslashes escaped.
    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func check(_ response: HTTPURLResponse, _ data: Data) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = ["msg", "message", "error_description", "error"].lazy.compactMap { object?[$0] as? String }.first
            ?? String(data: data, encoding: .utf8) ?? ""
        let code = (object?["code"] as? String) ?? (object?["error_code"] as? String)
        throw CloudError.server(status: response.statusCode, code: code, message: message)
    }
}
