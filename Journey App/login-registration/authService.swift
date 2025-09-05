import Foundation
import Combine
import CryptoKit

struct API {
    static let base = URL(string: "https://yourjourney.it.com")! // <- set this
}

struct HTTPError: Error { let status: Int; let data: Data }

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var email: String?
    @Published private(set) var userId: String?

    private var refreshTimer: Timer?

    init() {
        // Try to restore a session
        if let uid = Keychain.get(AuthKeys.userId).flatMap({ String(data:$0, encoding:.utf8) }),
           Keychain.get(AuthKeys.access) != nil {
            self.userId = uid
            self.isAuthenticated = true
            startTokenRefresher() // resume periodic refresh on app launch
        }
    }
    
    // MARK: registration/login
    func register(email: String, password: String) async throws {
        let json = try await post("/auth/register", body: ["email": email, "password": password])
        try handleAuthResponse(json)
    }

    // MARK: - Login / Logout

    func login(email: String, password: String) async throws {
        let json = try await post("/auth/login", body: ["email": email, "password": password])

        guard
          let user = json["user"] as? [String: Any],
          let uid  = user["id"] as? String,
          let tokens = json["tokens"] as? [String: Any],
          let access = tokens["accessToken"] as? String,
          let refresh = tokens["refreshToken"] as? String
        else { throw URLError(.cannotParseResponse) }

        _ = Keychain.set(Data(uid.utf8),     for: AuthKeys.userId)
        _ = Keychain.set(Data(access.utf8),  for: AuthKeys.access)
        _ = Keychain.set(Data(refresh.utf8), for: AuthKeys.refresh)

        self.userId = uid
        self.isAuthenticated = true

        startTokenRefresher()  // <-- start the 15-min cycle
    }

    func logout() async {
        if let refresh = Keychain.get(AuthKeys.refresh).flatMap({ String(data:$0, encoding:.utf8) }) {
            _ = try? await post("/auth/logout", body: ["refreshToken": refresh])
        }
        Keychain.remove(AuthKeys.userId)
        Keychain.remove(AuthKeys.access)
        Keychain.remove(AuthKeys.refresh)
        userId = nil
        isAuthenticated = false
        stopTokenRefresher()
    }

    // MARK: - Your two GETs (messages + summaries)

    // GET /history/:date -> { compressed_history: string }
    public func getCompressedHistory(for date: String) async throws -> String {
        let data = try await authedGET("/history/\(date)")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let s = json?["compressed_history"] as? String else { throw URLError(.cannotParseResponse) }
        return s
    }

    // GET /summaries/:date -> { summaries: [string] }
    public func getSummaries(for date: String) async throws -> [String] {
        let data = try await authedGET("/summaries/\(date)")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["summaries"] as? [String]) ?? []
    }
    
    // MARK: - Authenticated history post
    public func postCompressedHistory(
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

    // MARK: - Private networking helpers

    private func authedGET(_ path: String) async throws -> Data {
        // Pull the access token from Keychain
        guard let access = Keychain.get(AuthKeys.access).flatMap({ String(data:$0, encoding:.utf8) }) else {
            throw HTTPError(status: 401, data: Data())
        }

        var req = URLRequest(url: API.base.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        // If expired, do a one-shot refresh and retry once
        if http.statusCode == 401 {
            try await refreshTokens()
            return try await authedGET(path) // retry once after refresh
        }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, data: data)
        }
        return data
    }
    
    // MARK: - Authenticated POST (similar to authedGET)
    
    private func authedPOST(_ path: String, body: [String: Any]) async throws -> Data {
        guard let access = Keychain.get(AuthKeys.access).flatMap({ String(data:$0, encoding:.utf8) }) else {
            throw HTTPError(status: 401, data: Data())
        }

        var req = URLRequest(url: API.base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("POST URL: \(req.url?.absoluteString ?? "unknown url")")
        print("POST Body: \(String(data: req.httpBody ?? Data(), encoding: .utf8) ?? "invalid body")")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if http.statusCode == 401 {
            try await refreshTokens()
            return try await authedPOST(path, body: body) // retry once
        }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, data: data)
        }
        return data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: API.base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("POST URL: \(req.url?.absoluteString ?? "unknown url")")
        print("POST Body: \(String(data: req.httpBody ?? Data(), encoding: .utf8) ?? "invalid body")")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let bodyString = String(data: data, encoding: .utf8) ?? "unable to decode body"
            print("POST Error: status=\(code), body=\(bodyString)")
            throw HTTPError(status: code, data: data)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Token refresh (manual + periodic)

    public func refreshTokens() async throws {
        guard
          let uid = Keychain.get(AuthKeys.userId).flatMap({ String(data:$0, encoding:.utf8) }),
          let refresh = Keychain.get(AuthKeys.refresh).flatMap({ String(data:$0, encoding:.utf8) })
        else { throw HTTPError(status: 401, data: Data()) }

        let resp = try await post("/auth/refresh", body: ["userId": uid, "refreshToken": refresh])

        guard
          let tokens = resp["tokens"] as? [String: Any],
          let newAccess = tokens["accessToken"] as? String,
          let newRefresh = tokens["refreshToken"] as? String
        else {
            print("Error parsing refresh response: \(resp)")
            throw URLError(.cannotParseResponse)
        }

        _ = Keychain.set(Data(newAccess.utf8), for: AuthKeys.access)
        _ = Keychain.set(Data(newRefresh.utf8), for: AuthKeys.refresh)
    }

    public func startTokenRefresher() {
        stopTokenRefresher()
        // refresh slightly before 15 minutes (e.g., every 14m)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 14 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                // Silently try to refresh; if it fails, we’ll catch it on next request as 401.
                try? await self.refreshTokens()
            }
        }
    }

    private func stopTokenRefresher() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func handleAuthResponse(_ json: [String: Any]) throws {
            print("Auth Response JSON: \(json)")
            guard
              let user = json["user"] as? [String: Any],
              let uid = user["id"] as? String,
              let em  = user["email"] as? String,
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["accessToken"] as? String
            else { throw URLError(.cannotParseResponse) }

            // refresh token is optional if your backend doesn’t use it yet
            let refresh = (tokens["refreshToken"] as? String) ?? ""

            _ = Keychain.set(Data(uid.utf8), for: AuthKeys.userId)
            _ = Keychain.set(Data(em.utf8),  for: AuthKeys.email)
            _ = Keychain.set(Data(access.utf8), for: AuthKeys.access)
            if !refresh.isEmpty { _ = Keychain.set(Data(refresh.utf8), for: AuthKeys.refresh) }

            self.userId = uid
            self.email  = em
            self.isAuthenticated = true
        }
}
