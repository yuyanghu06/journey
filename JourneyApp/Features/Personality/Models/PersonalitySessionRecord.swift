import Foundation
import SwiftData

// MARK: - PersonalityMessageRecord (SwiftData)
// Persists a single turn in a Past Self simulation session.

@Model
final class PersonalityMessageRecord {
    var id: UUID
    var role: String              // "user" | "past_self"
    var text: String
    var timestamp: Date
    var activeTokens: [String]

    init(id: UUID = UUID(), role: String, text: String, timestamp: Date = Date(), activeTokens: [String] = []) {
        self.id           = id
        self.role         = role
        self.text         = text
        self.timestamp    = timestamp
        self.activeTokens = activeTokens
    }

    func toPersonalityMessage() -> PersonalityMessage {
        PersonalityMessage(
            id:           id,
            role:         PersonalityRole(rawValue: role) ?? .user,
            text:         text,
            timestamp:    timestamp,
            activeTokens: activeTokens
        )
    }
}

// MARK: - PersonalitySessionRecord (SwiftData)

@Model
final class PersonalitySessionRecord {
    var id: UUID
    var modelVersionId: UUID?
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var messages: [PersonalityMessageRecord]

    init(id: UUID = UUID(), modelVersionId: UUID? = nil, createdAt: Date = Date()) {
        self.id             = id
        self.modelVersionId = modelVersionId
        self.createdAt      = createdAt
        self.messages       = []
    }

    func toPersonalitySession(modelVersion: PersonalityModelVersion? = nil) -> PersonalitySession {
        PersonalitySession(
            id:           id,
            modelVersion: modelVersion,
            messages:     messages.sorted { $0.timestamp < $1.timestamp }.map { $0.toPersonalityMessage() },
            createdAt:    createdAt
        )
    }
}
