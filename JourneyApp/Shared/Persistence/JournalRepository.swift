import Foundation

// MARK: - JournalEntry

/// A generated AI journal summary for a single calendar day.
struct JournalEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let dayKey: DayKey
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), dayKey: DayKey, text: String, createdAt: Date = Date()) {
        self.id        = id
        self.dayKey    = dayKey
        self.text      = text
        self.createdAt = createdAt
    }
}

// MARK: - JournalRepositoryProtocol

/// Defines the contract for reading and writing journal entries keyed by DayKey.
protocol JournalRepositoryProtocol: AnyObject {
    /// Returns the journal entry for the given day, or nil if none exists.
    func fetchJournalEntry(dayKey: DayKey) async -> JournalEntry?

    /// Creates or replaces the journal entry for the given day.
    func upsertJournalEntry(_ entry: JournalEntry) async

    /// Deletes the journal entry for the given day, if any.
    func deleteJournalEntry(dayKey: DayKey) async

    /// Returns all DayKeys that have a stored journal entry.
    func listDaysWithJournalEntries() async -> [DayKey]
}

// MARK: - InMemoryJournalRepository

/// A simple in-memory implementation used until the SwiftData or remote-backed
/// repository is wired up. Data does not survive app restarts.
final class InMemoryJournalRepository: JournalRepositoryProtocol {

    private var store: [String: JournalEntry] = [:]

    func fetchJournalEntry(dayKey: DayKey) async -> JournalEntry? {
        store[dayKey.rawValue]
    }

    func upsertJournalEntry(_ entry: JournalEntry) async {
        store[entry.dayKey.rawValue] = entry
    }

    func deleteJournalEntry(dayKey: DayKey) async {
        store.removeValue(forKey: dayKey.rawValue)
    }

    func listDaysWithJournalEntries() async -> [DayKey] {
        store.keys.map { DayKey(rawValue: $0) }
    }
}
