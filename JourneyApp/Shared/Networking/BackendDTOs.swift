import Foundation

// MARK: - BackendDTOs
// Decodable types that mirror the backend's GET /days/:dayKey response.
// Used by ChatViewModel (today's history on launch) and DayDetailViewModel
// (any day's data when the calendar detail screen opens).

struct BackendMessageDTO: Decodable {
    let id: String
    let dayKey: String
    let role: String
    let text: String
    let timestamp: String

    /// Maps to the local Message model.
    func toMessage() -> Message {
        Message(
            id: UUID(uuidString: id) ?? UUID(),
            dayKey: DayKey(dayKey),
            role: MessageRole(rawValue: role) ?? .assistant,
            text: text,
            timestamp: ISO8601DateFormatter().date(from: timestamp) ?? Date(),
            status: .delivered
        )
    }
}

struct BackendConversationDTO: Decodable {
    let dayKey: String
    let messages: [BackendMessageDTO]
}

struct BackendJournalEntryDTO: Decodable {
    let id: String
    let dayKey: String
    let text: String
    let createdAt: String
    let updatedAt: String

    /// Maps to the local JournalEntry model.
    func toJournalEntry() -> JournalEntry {
        JournalEntry(
            id: UUID(uuidString: id) ?? UUID(),
            dayKey: DayKey(dayKey),
            text: text,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date()
        )
    }
}

struct DayDataResponse: Decodable {
    let conversation: BackendConversationDTO
    let journalEntry: BackendJournalEntryDTO?
}

// MARK: - Personality DTOs

struct PersonalityHistoryMessageDTO: Encodable {
    let dayKey: String
    let role: String
    let text: String
}

struct PersonalitySendMessageRequest: Encodable {
    let dayKey: String
    let userText: String
    let personalityTokens: [String]
    let clientMessageId: String?
    /// All messages from the last 14 days, providing the AI full conversational context.
    let conversationHistory: [PersonalityHistoryMessageDTO]
    /// Raw text from the user's saved memory/context documents.
    let memories: [String]
}

struct PersonalityMessageResponse: Decodable {
    let id: String
    let dayKey: String
    let role: String
    let text: String
    let timestamp: String
}

struct PersonalitySendMessageResponse: Decodable {
    let assistantMessage: PersonalityMessageResponse
}
