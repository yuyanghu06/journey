import Foundation
import SwiftData

// MARK: - MessageRecord
// SwiftData model for persisting chat messages across app restarts.
// Mirrors the `Message` value type — acts as the durable backing store.

@Model
final class MessageRecord {

    @Attribute(.unique) var id: String
    var dayKey:    String
    var role:      String
    var text:      String
    var timestamp: Date
    var status:    String

    init(from message: Message) {
        self.id        = message.id.uuidString
        self.dayKey    = message.dayKey.rawValue
        self.role      = message.role.rawValue
        self.text      = message.text
        self.timestamp = message.timestamp
        self.status    = message.status.rawValue
    }

    func toMessage() -> Message {
        Message(
            id:        UUID(uuidString: id) ?? UUID(),
            dayKey:    DayKey(dayKey),
            role:      MessageRole(rawValue: role) ?? .assistant,
            text:      text,
            timestamp: timestamp,
            status:    Message.Status(rawValue: status) ?? .sent
        )
    }
}
