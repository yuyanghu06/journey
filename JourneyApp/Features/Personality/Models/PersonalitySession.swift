import Foundation

// MARK: - PersonalityMessage
// A single turn in a Past Self simulation session.

struct PersonalityMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: PersonalityRole
    let text: String
    let timestamp: Date
    let activeTokens: [String]  // personality tokens active at time of send

    init(
        id: UUID = UUID(),
        role: PersonalityRole,
        text: String,
        timestamp: Date = Date(),
        activeTokens: [String] = []
    ) {
        self.id           = id
        self.role         = role
        self.text         = text
        self.timestamp    = timestamp
        self.activeTokens = activeTokens
    }

    var isFromCurrentUser: Bool { role == .user }
}

enum PersonalityRole: String, Codable, Hashable {
    case user
    case pastSelf = "past_self"
}

// MARK: - PersonalitySession
// An in-memory representation of one simulation conversation.

struct PersonalitySession: Identifiable {
    let id: UUID
    let modelVersion: PersonalityModelVersion?
    var messages: [PersonalityMessage]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        modelVersion: PersonalityModelVersion? = nil,
        messages: [PersonalityMessage] = [],
        createdAt: Date = Date()
    ) {
        self.id           = id
        self.modelVersion = modelVersion
        self.messages     = messages
        self.createdAt    = createdAt
    }
}
