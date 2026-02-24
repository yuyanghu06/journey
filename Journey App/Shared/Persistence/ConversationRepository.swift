import Foundation

// MARK: - DayConversation

/// A snapshot of all messages belonging to a single calendar day.
struct DayConversation {
    let dayKey: DayKey
    var messages: [Message]
}

// MARK: - ConversationRepositoryProtocol

/// Defines the contract for reading and writing chat conversations keyed by DayKey.
/// Implementations may be backed by in-memory storage, SwiftData, or a remote API.
protocol ConversationRepositoryProtocol: AnyObject {
    /// Returns the full conversation for the given day, or an empty conversation if none exists.
    func fetchConversation(dayKey: DayKey) async -> DayConversation

    /// Appends a single message to the stored conversation for the given day.
    func appendMessage(_ message: Message, dayKey: DayKey) async

    /// Replaces the entire message list for the given day (used when syncing from backend).
    func setMessages(_ messages: [Message], dayKey: DayKey) async

    /// Returns all DayKeys that have at least one stored message.
    func listDaysWithConversations() async -> [DayKey]
}

// MARK: - InMemoryConversationRepository

/// A simple in-memory implementation used until the SwiftData or remote-backed
/// repository is wired up. Data does not survive app restarts.
final class InMemoryConversationRepository: ConversationRepositoryProtocol {

    // Keyed by DayKey.rawValue for fast lookup
    private var store: [String: [Message]] = [:]

    func fetchConversation(dayKey: DayKey) async -> DayConversation {
        let messages = store[dayKey.rawValue] ?? []
        return DayConversation(dayKey: dayKey, messages: messages)
    }

    func appendMessage(_ message: Message, dayKey: DayKey) async {
        store[dayKey.rawValue, default: []].append(message)
    }

    func setMessages(_ messages: [Message], dayKey: DayKey) async {
        store[dayKey.rawValue] = messages
    }

    func listDaysWithConversations() async -> [DayKey] {
        store.compactMap { key, messages in
            messages.isEmpty ? nil : DayKey(rawValue: key)
        }
    }
}
