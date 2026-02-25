import Foundation
import Combine

// MARK: - AuthService
// Manages the authentication lifecycle: registration, login, logout,
// and automatic token refresh. Publishes `isAuthenticated` so the
// root view can react without polling.

@MainActor
final class AuthService: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var email: String?
    @Published private(set) var userId: String?

    // MARK: - Private

    private var refreshTimer: Timer?
    private let baseURL = URL(string: "https://yourjourney.it.com")!

    // MARK: - Init

    init() {
        // Restore session from Keychain if tokens are present
        if let uid = Keychain.get(AuthKeys.userId).flatMap({ String(data: $0, encoding: .utf8) }),
           Keychain.get(AuthKeys.access) != nil {
            self.userId          = uid
            self.email           = Keychain.get(AuthKeys.email).flatMap { String(data: $0, encoding: .utf8) }
            self.isAuthenticated = true
            startTokenRefresher()
        }
    }

    // MARK: - Register

    func register(email: String, password: String) async throws {
        let json = try await publicPost(
            "/auth/register",
            body: ["email": email, "password": password]
        )
        try handleAuthResponse(json)
    }

    // MARK: - Login

    func login(email: String, password: String) async throws {
        let json = try await publicPost(
            "/auth/login",
            body: ["email": email, "password": password]
        )
        try handleAuthResponse(json)
    }

    // MARK: - Logout

    func logout() async {
        // Best-effort server-side invalidation — ignore errors
        if let refresh = Keychain.get(AuthKeys.refresh).flatMap({ String(data: $0, encoding: .utf8) }) {
            _ = try? await publicPost("/auth/logout", body: ["refreshToken": refresh])
        }
        clearSession()
    }

    // MARK: - Token Refresh

    /// Performs a one-shot token refresh using the stored refresh token.
    func refreshTokens() async throws {
        guard
            let uid     = Keychain.get(AuthKeys.userId).flatMap({ String(data: $0, encoding: .utf8) }),
            let refresh = Keychain.get(AuthKeys.refresh).flatMap({ String(data: $0, encoding: .utf8) })
        else { throw HTTPError(status: 401, data: Data()) }

        let json = try await publicPost(
            "/auth/refresh",
            body: ["userId": uid, "refreshToken": refresh]
        )

        guard
            let tokens     = json["tokens"] as? [String: Any],
            let newAccess  = tokens["accessToken"]  as? String,
            let newRefresh = tokens["refreshToken"] as? String
        else { throw URLError(.cannotParseResponse) }

        Keychain.set(Data(newAccess.utf8),  for: AuthKeys.access)
        Keychain.set(Data(newRefresh.utf8), for: AuthKeys.refresh)
    }

    /// Starts a repeating timer that refreshes tokens every 14 minutes,
    /// keeping them valid ahead of the 15-minute server expiry.
    func startTokenRefresher() {
        stopTokenRefresher()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 14 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { try? await self.refreshTokens() }
        }
    }

    // MARK: - History / Summaries (backend I/O)

    /// GET /history/:date — returns the base64-encoded compressed message history.
    func getCompressedHistory(for date: String) async throws -> String {
        let data = try await authedGET("/history/\(date)")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let s = json?["compressed_history"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return s
    }

    /// GET /summaries/:date — returns the list of journal summary strings.
    func getSummaries(for date: String) async throws -> [String] {
        let data = try await authedGET("/summaries/\(date)")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["summaries"] as? [String]) ?? []
    }

    /// POST /history — persists the compressed message history and summary.
    func postCompressedHistory(
        date: String,
        compressedHistory: String,
        summary: String
    ) async throws {
        let payload: [String: Any] = [
            "date": date,
            "compressedHistory": compressedHistory,
            "summary": summary
        ]
        _ = try await authedPOST("/history", body: payload)
    }

    // MARK: - Private networking

    /// Unauthenticated POST — used for auth endpoints (login, register, refresh).
    private func publicPost(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody   = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, data: data)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Authenticated GET — injects Bearer token and retries once on 401.
    private func authedGET(_ path: String) async throws -> Data {
        guard let access = Keychain.get(AuthKeys.access).flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw HTTPError(status: 401, data: Data())
        }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 {
            try await refreshTokens()
            return try await authedGET(path)
        }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, data: data)
        }
        return data
    }

    /// Authenticated POST — injects Bearer token and retries once on 401.
    private func authedPOST(_ path: String, body: [String: Any]) async throws -> Data {
        guard let access = Keychain.get(AuthKeys.access).flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw HTTPError(status: 401, data: Data())
        }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(access)",   forHTTPHeaderField: "Authorization")
        req.httpBody   = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 {
            try await refreshTokens()
            return try await authedPOST(path, body: body)
        }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, data: data)
        }
        return data
    }

    // MARK: - Helpers

    /// Parses a successful auth response JSON and writes tokens + user info to Keychain.
    private func handleAuthResponse(_ json: [String: Any]) throws {
        guard
            let user   = json["user"]   as? [String: Any],
            let uid    = user["id"]     as? String,
            let em     = user["email"]  as? String,
            let tokens = json["tokens"] as? [String: Any],
            let access = tokens["accessToken"] as? String
        else { throw URLError(.cannotParseResponse) }

        let refresh = (tokens["refreshToken"] as? String) ?? ""

        Keychain.set(Data(uid.utf8),     for: AuthKeys.userId)
        Keychain.set(Data(em.utf8),      for: AuthKeys.email)
        Keychain.set(Data(access.utf8),  for: AuthKeys.access)
        if !refresh.isEmpty {
            Keychain.set(Data(refresh.utf8), for: AuthKeys.refresh)
        }

        self.userId          = uid
        self.email           = em
        self.isAuthenticated = true
        startTokenRefresher()
    }

    /// Wipes all Keychain tokens and resets published state.
    private func clearSession() {
        Keychain.remove(AuthKeys.userId)
        Keychain.remove(AuthKeys.email)
        Keychain.remove(AuthKeys.access)
        Keychain.remove(AuthKeys.refresh)
        userId          = nil
        email           = nil
        isAuthenticated = false
        stopTokenRefresher()
    }

    private func stopTokenRefresher() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
