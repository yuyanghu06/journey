import Foundation

// MARK: - MessageRole

/// The sender role of a chat message — mirrors OpenAI's role convention.
enum MessageRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

// MARK: - Message

/// A single chat message in a day's conversation thread.
/// Conforms to Codable so it can be serialised for backend storage.
struct Message: Identifiable, Hashable, Codable {
    let id: UUID
    let dayKey: DayKey
    let role: MessageRole
    let text: String
    let timestamp: Date
    var status: Status

    /// Convenience flag — true when this message was authored by the local user.
    var isFromCurrentUser: Bool { role == .user }

    // MARK: Status

    /// Delivery status displayed below user messages.
    enum Status: String, Codable, Hashable {
        case sending, sent, delivered, read
    }

    // MARK: Init

    init(
        id: UUID = UUID(),
        dayKey: DayKey = .today,
        role: MessageRole,
        text: String,
        timestamp: Date = Date(),
        status: Status = .sent
    ) {
        self.id        = id
        self.dayKey    = dayKey
        self.role      = role
        self.text      = text
        self.timestamp = timestamp
        self.status    = status
    }
}

// MARK: - LegacyCodableMessage

/// Used only when decoding old compressed history that pre-dates the role-based model.
struct LegacyCodableMessage: Codable {
    var text: String
    var isFromCurrentUser: Bool
    var timestamp: Date
    var status: String

    /// Converts this legacy record into the current `Message` type.
    func toMessage() -> Message {
        Message(
            role: isFromCurrentUser ? .user : .assistant,
            text: text,
            timestamp: timestamp,
            status: Message.Status(rawValue: status) ?? .sent
        )
    }
}
