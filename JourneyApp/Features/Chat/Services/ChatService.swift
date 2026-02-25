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
        let dto = SendMessageRequest(dayKey: dayKey, userText: userText)
        let response = try? await apiClient.post("/chat/sendMessage", body: dto, responseType: SendMessageResponse.self)
        return response?.assistantMessage.text ?? "I'm here. Tell me more."
    }

    // MARK: - Generate journal entry

    /// Calls POST /journal/generate and returns the journal entry text.
    /// Returns an empty string when the backend is unreachable.
    func generateJournalEntry(
        dayKey: DayKey,
        messages: [Message]
    ) async -> String {
        let dto = GenerateJournalRequest(dayKey: dayKey, messages: messages)
        let response = try? await apiClient.post("/journal/generate", body: dto, responseType: GenerateJournalResponse.self)
        return response?.journalEntry.text ?? ""
    }
}

// MARK: - Request / Response DTOs

/// Request body for POST /chat/sendMessage
private struct SendMessageRequest: Encodable {
    let dayKey: String
    let userText: String

    init(dayKey: DayKey, userText: String) {
        self.dayKey   = dayKey.rawValue
        self.userText = userText
    }
}

private struct AssistantMessageDTO: Decodable {
    let id: String
    let dayKey: String
    let role: String
    let text: String
    let timestamp: String
}

private struct SendMessageResponse: Decodable {
    let assistantMessage: AssistantMessageDTO
}

/// Request body for POST /journal/generate
private struct GenerateJournalRequest: Encodable {
    let dayKey: String
    let messages: [MessageDTO]
    init(dayKey: DayKey, messages: [Message]) {
        self.dayKey    = dayKey.rawValue
        self.messages  = messages.map { MessageDTO($0) }
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

private struct JournalEntryDTO: Decodable {
    let id: String
    let dayKey: String
    let text: String
    let createdAt: String
    let updatedAt: String
}

private struct GenerateJournalResponse: Decodable {
    let journalEntry: JournalEntryDTO
}
