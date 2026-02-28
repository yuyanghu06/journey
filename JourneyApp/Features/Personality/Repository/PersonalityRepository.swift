import Foundation
import SwiftData

// MARK: - PersonalityRepositoryProtocol

protocol PersonalityRepositoryProtocol: AnyObject {
    func saveSession(_ session: PersonalitySessionRecord) async
    func fetchSessions() async -> [PersonalitySessionRecord]
    func deleteSession(_ id: UUID) async

    func saveContextDocument(_ doc: ContextDocument) async
    func fetchContextDocuments() async -> [ContextDocument]
    func deleteContextDocument(_ id: UUID) async
}

// MARK: - InMemoryPersonalityRepository
// Used as a fallback and in previews/tests before SwiftData container is available.
// Actor isolation protects mutable dictionaries from concurrent access.

actor InMemoryPersonalityRepository: PersonalityRepositoryProtocol {

    private var sessions:  [UUID: PersonalitySessionRecord]  = [:]
    private var documents: [UUID: ContextDocument] = [:]

    func saveSession(_ session: PersonalitySessionRecord) async {
        sessions[session.id] = session
    }

    func fetchSessions() async -> [PersonalitySessionRecord] {
        Array(sessions.values).sorted { $0.createdAt > $1.createdAt }
    }

    func deleteSession(_ id: UUID) async {
        sessions.removeValue(forKey: id)
    }

    func saveContextDocument(_ doc: ContextDocument) async {
        documents[doc.id] = doc
    }

    func fetchContextDocuments() async -> [ContextDocument] {
        Array(documents.values).sorted { $0.createdAt > $1.createdAt }
    }

    func deleteContextDocument(_ id: UUID) async {
        documents.removeValue(forKey: id)
    }
}

// MARK: - SwiftDataPersonalityRepository
// Production implementation backed by the app's SwiftData ModelContext.

@MainActor
final class SwiftDataPersonalityRepository: PersonalityRepositoryProtocol {

    /// Shared instance backed by the app's main ModelContext.
    static let shared = SwiftDataPersonalityRepository(
        context: AppModelContainer.shared.mainContext
    )

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Sessions

    func saveSession(_ session: PersonalitySessionRecord) async {
        context.insert(session)
        try? context.save()
    }

    func fetchSessions() async -> [PersonalitySessionRecord] {
        let descriptor = FetchDescriptor<PersonalitySessionRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func deleteSession(_ id: UUID) async {
        let descriptor = FetchDescriptor<PersonalitySessionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try? context.fetch(descriptor).first {
            context.delete(record)
            try? context.save()
        }
    }

    // MARK: - Context Documents

    func saveContextDocument(_ doc: ContextDocument) async {
        context.insert(doc)
        try? context.save()
    }

    func fetchContextDocuments() async -> [ContextDocument] {
        let descriptor = FetchDescriptor<ContextDocument>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func deleteContextDocument(_ id: UUID) async {
        let descriptor = FetchDescriptor<ContextDocument>(
            predicate: #Predicate { $0.id == id }
        )
        if let doc = try? context.fetch(descriptor).first {
            context.delete(doc)
            try? context.save()
        }
    }
}
