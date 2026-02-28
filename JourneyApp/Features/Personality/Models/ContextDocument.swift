import Foundation
import SwiftData

// MARK: - ContextDocument (SwiftData)
// An external memory note or imported document fed into personality training.

@Model
final class ContextDocument {
    var id: UUID
    var title: String
    var rawText: String
    var createdAt: Date

    /// Always reflects the current rawText — computed so it never goes stale.
    var characterCount: Int { rawText.count }

    init(
        id: UUID = UUID(),
        title: String,
        rawText: String,
        createdAt: Date = Date()
    ) {
        self.id        = id
        self.title     = title
        self.rawText   = rawText
        self.createdAt = createdAt
    }

    /// First ~100 characters for list previews.
    var preview: String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 100 else { return trimmed }
        return String(trimmed.prefix(100)) + "…"
    }
}
