import Foundation

// MARK: - ChatServiceProtocol

/// Defines the AI interaction boundary.
/// The iOS app never calls AI providers directly — all intelligence flows
/// through the backend endpoints. Swap the implementation here when the
/// backend is ready; nothing else in the codebase needs to change.
protocol ChatServiceProtocol {
    /// Sends the user's message along with prior context and returns the assistant reply.
    /// Maps to POST /chat/sendMessage on the backend.
    func sendMessage(
        dayKey: DayKey,
        userText: String,
        priorMessages: [Message]
    ) async -> String

    /// Generates a journal entry from the day's conversation.
    /// Maps to POST /journal/generate on the backend.
    func generateJournalEntry(
        dayKey: DayKey,
        messages: [Message]
    ) async -> String
}

// MARK: - ChatService

/// Production implementation that routes all requests through the typed APIClient.
/// Currently returns stub responses until the backend /chat and /journal endpoints
/// are deployed.
final class ChatService: ChatServiceProtocol {

    // MARK: - Dependencies

    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - Send message

    /// Calls POST /chat/sendMessage and returns the assistant's reply text.
    /// Falls back to a friendly placeholder when the backend is unreachable.
    func sendMessage(
        dayKey: DayKey,
        userText: String,
        priorMessages: [Message]
    ) async -> String {
        // TODO: Uncomment when backend is live:
        // let dto = SendMessageRequest(dayKey: dayKey, text: userText, history: priorMessages)
        // let response = try? await apiClient.post("/chat/sendMessage", body: dto, responseType: SendMessageResponse.self)
        // return response?.reply ?? fallback

        // Stub: returns a warm placeholder until the backend is connected.
        return stubReply(for: userText)
    }

    // MARK: - Generate journal entry

    /// Calls POST /journal/generate and returns the journal entry text.
    /// Returns an empty string when the backend is unreachable.
    func generateJournalEntry(
        dayKey: DayKey,
        messages: [Message]
    ) async -> String {
        // TODO: Uncomment when backend is live:
        // let userMessages = messages.filter { $0.role == .user }.map { $0.text }
        // let dto = GenerateJournalRequest(dayKey: dayKey, messages: userMessages)
        // let response = try? await apiClient.post("/journal/generate", body: dto, responseType: GenerateJournalResponse.self)
        // return response?.entry ?? ""

        // Stub: placeholder journal text until the backend is connected.
        return "Your thoughts from today will appear here once the journal service is connected."
    }

    // MARK: - Private

    /// Cycles through friendly prompts so the stub still feels conversational.
    private func stubReply(for text: String) -> String {
        let replies = [
            "That's really interesting — tell me more about that.",
            "How did that make you feel?",
            "It sounds like today had a lot going on. What stood out most?",
            "I hear you. What do you think you'll do differently next time?",
            "Thanks for sharing that. What else is on your mind?",
            "That's a great reflection. What are you looking forward to tomorrow?"
        ]
        return replies[abs(text.hashValue) % replies.count]
    }
}

// MARK: - Request / Response DTOs (ready for when backend is wired up)

/// Request body for POST /chat/sendMessage
private struct SendMessageRequest: Encodable {
    let dayKey: String
    let text: String
    let history: [MessageDTO]

    init(dayKey: DayKey, text: String, history: [Message]) {
        self.dayKey   = dayKey.rawValue
        self.text     = text
        self.history  = history.map { MessageDTO($0) }
    }
}

private struct MessageDTO: Encodable {
    let role: String
    let text: String
    init(_ message: Message) {
        self.role = message.role.rawValue
        self.text = message.text
    }
}

private struct SendMessageResponse: Decodable {
    let reply: String
}

/// Request body for POST /journal/generate
private struct GenerateJournalRequest: Encodable {
    let dayKey: String
    let messages: [String]
    init(dayKey: DayKey, messages: [String]) {
        self.dayKey   = dayKey.rawValue
        self.messages = messages
    }
}

private struct GenerateJournalResponse: Decodable {
    let entry: String
}
