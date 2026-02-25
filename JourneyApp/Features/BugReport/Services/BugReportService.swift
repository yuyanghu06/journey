import Foundation

// MARK: - BugReportServiceProtocol

/// Defines the contract for submitting bug reports.
protocol BugReportServiceProtocol {
    /// Sends a bug report with the given description to the backend.
    func submitReport(description: String) async throws
}

// MARK: - BugReportService

/// Production implementation that POSTs a bug report to the backend.
final class BugReportService: BugReportServiceProtocol {

    // MARK: - Errors

    enum BugReportError: LocalizedError {
        case invalidURL
        case encodingFailed
        case invalidResponse
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:        return "Invalid server URL."
            case .encodingFailed:    return "Failed to encode the report."
            case .invalidResponse:   return "Unexpected server response."
            case .serverError(let c): return "Server returned error \(c)."
            }
        }
    }

    // MARK: - Submit

    /// Posts the bug report to POST /bugs/report.
    func submitReport(description: String) async throws {
        guard let url = URL(string: "https://yourjourney.it.com/bugs/report") else {
            throw BugReportError.invalidURL
        }

        let payload: [String: Any] = [
            "date":        DayKey.today.rawValue,
            "description": description,
            "status":      "not-fulfilled"
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw BugReportError.encodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BugReportError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw BugReportError.serverError(http.statusCode)
        }
    }
}
