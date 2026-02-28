import Foundation
import SwiftData

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
///
/// `SwiftDataConversationRepository.shared` is now the production default.
/// `InMemoryConversationRepository` is retained for unit tests and previews.
final class InMemoryConversationRepository: ConversationRepositoryProtocol {

    /// Single shared instance — must be used as the default across all ViewModels.
    static let shared = InMemoryConversationRepository()

    // Keyed by DayKey.rawValue for fast lookup
    private var store: [String: [Message]] = [:]

    /// Private to enforce use of `.shared` for the default path.
    /// Tests may still create isolated instances with `InMemoryConversationRepository()`.
    init() {}

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

// MARK: - SwiftDataConversationRepository

/// Persistent implementation backed by SwiftData's `MessageRecord`.
/// Messages survive app restarts and are available to all features (Chat, Personality, Calendar).
///
/// Use `SwiftDataConversationRepository.shared` as the default everywhere.

@MainActor
final class SwiftDataConversationRepository: ConversationRepositoryProtocol {

    static let shared = SwiftDataConversationRepository()

    private let context: ModelContext

    init(context: ModelContext = ModelContext(AppModelContainer.shared)) {
        self.context = context
    }

    func fetchConversation(dayKey: DayKey) async -> DayConversation {
        let key = dayKey.rawValue
        var descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 500
        let records = (try? context.fetch(descriptor)) ?? []
        return DayConversation(dayKey: dayKey, messages: records.map { $0.toMessage() })
    }

    func appendMessage(_ message: Message, dayKey: DayKey) async {
        // Skip if already stored (idempotent — avoids duplicates on retry)
        let idStr = message.id.uuidString
        let dup = FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == idStr })
        guard (try? context.fetch(dup).isEmpty) == true else { return }
        context.insert(MessageRecord(from: message))
        try? context.save()
    }

    func setMessages(_ messages: [Message], dayKey: DayKey) async {
        let key = dayKey.rawValue
        // Remove old records for this day, then insert fresh set
        let existing = FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.dayKey == key })
        (try? context.fetch(existing))?.forEach { context.delete($0) }
        messages.forEach { context.insert(MessageRecord(from: $0)) }
        try? context.save()
    }

    func listDaysWithConversations() async -> [DayKey] {
        let descriptor = FetchDescriptor<MessageRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        let unique  = Set(records.map { $0.dayKey })
        return unique.compactMap { DayKey(rawValue: $0) }
    }
}
