import Foundation

// MARK: - APIClientProtocol
// Defines the contract for all network communication.
// Using a protocol allows easy substitution of mock clients in tests.

protocol APIClientProtocol {
    /// Performs an authenticated GET and decodes the response body.
    func get<Response: Decodable>(_ path: String, responseType: Response.Type) async throws -> Response

    /// Performs an authenticated POST with a JSON body and decodes the response.
    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response

    /// Performs an authenticated POST with a raw dictionary body and decodes the response.
    func postRaw<Response: Decodable>(
        _ path: String,
        body: [String: Any],
        responseType: Response.Type
    ) async throws -> Response

    /// Performs an unauthenticated POST (e.g., login, register).
    func postPublic<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response
}

// MARK: - HTTPError

/// A structured error that carries the HTTP status code and raw response body.
struct HTTPError: Error {
    let status: Int
    let data: Data

    var localizedDescription: String {
        "HTTP \(status)"
    }
}

// MARK: - APIClient

/// Production implementation of APIClientProtocol backed by URLSession.
/// Automatically attaches the stored Bearer token to authenticated requests
/// and retries once after a 401 by attempting a token refresh.
final class APIClient: APIClientProtocol {

    // MARK: - Singleton

    static let shared = APIClient()

    // MARK: - Configuration

    private let baseURL: URL

    /// Injected token provider — defaults to reading from Keychain.
    var tokenProvider: TokenProviderProtocol

    init(
        baseURL: URL = URL(string: "https://journey-production-47d5.up.railway.app/")!,
        tokenProvider: TokenProviderProtocol = KeychainTokenProvider()
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    // MARK: - GET

    func get<Response: Decodable>(_ path: String, responseType: Response.Type) async throws -> Response {
        let request = try buildRequest(path: path, method: "GET", body: Optional<Data>.none, authenticated: true)
        return try await perform(request, responseType: responseType, retryOn401: true)
    }

    // MARK: - POST (Encodable body)

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        let bodyData = try JSONEncoder().encode(body)
        let request  = try buildRequest(path: path, method: "POST", body: bodyData, authenticated: true)
        return try await perform(request, responseType: responseType, retryOn401: true)
    }

    // MARK: - POST (raw dictionary body)

    func postRaw<Response: Decodable>(
        _ path: String,
        body: [String: Any],
        responseType: Response.Type
    ) async throws -> Response {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request  = try buildRequest(path: path, method: "POST", body: bodyData, authenticated: true)
        return try await perform(request, responseType: responseType, retryOn401: true)
    }

    // MARK: - POST (public — no auth header)

    func postPublic<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        let bodyData = try JSONEncoder().encode(body)
        let request  = try buildRequest(path: path, method: "POST", body: bodyData, authenticated: false)
        return try await perform(request, responseType: responseType, retryOn401: false)
    }

    // MARK: - Private helpers

    /// Builds a URLRequest, optionally attaching a Bearer token.
    private func buildRequest(
        path: String,
        method: String,
        body: Data?,
        authenticated: Bool
    ) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        if authenticated {
            guard let token = tokenProvider.accessToken else {
                throw HTTPError(status: 401, data: Data())
            }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// Executes a request, decodes the response, and optionally retries once on 401.
    private func perform<Response: Decodable>(
        _ request: URLRequest,
        responseType: Response.Type,
        retryOn401: Bool
    ) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Refresh tokens and retry once on 401
        if http.statusCode == 401 && retryOn401 {
            try await tokenProvider.refreshTokens()
            return try await perform(request, responseType: responseType, retryOn401: false)
        }

        guard (200...299).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, data: data)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

// MARK: - TokenProviderProtocol

/// Abstracts token storage so APIClient can be tested without Keychain access.
protocol TokenProviderProtocol {
    var accessToken: String? { get }
    func refreshTokens() async throws
}

// MARK: - KeychainTokenProvider

/// Production token provider backed by the app's Keychain store.
final class KeychainTokenProvider: TokenProviderProtocol {

    var accessToken: String? {
        Keychain.get(AuthKeys.access).flatMap { String(data: $0, encoding: .utf8) }
    }

    func refreshTokens() async throws {
        // Delegate to AuthService's shared refresh logic.
        // In a real app this would use a DI container; here we use a notification or shared service.
        // TODO: Wire up via dependency injection when AuthService is refactored to use APIClient.
    }
}
