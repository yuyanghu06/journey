import Foundation

// MARK: - MessageCompressor
// Serializes and deserializes message arrays as base64-encoded JSON for
// backend storage. Used when syncing conversation history with the API.

enum MessageCompressor {

    // MARK: - Compress

    /// Encodes a message array into a base64 string. Returns nil on failure.
    static func compress(_ messages: [Message]) -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(messages)
            return data.base64EncodedString()
        } catch {
            print("[MessageCompressor] Encode failed: \(error)")
            return nil
        }
    }

    // MARK: - Decompress

    /// Decodes a base64 string back into messages.
    /// Falls back to a legacy format, then returns a default welcome message on failure.
    static func decompress(_ compressed: String) -> [Message] {
        guard !compressed.isEmpty,
              let data = Data(base64Encoded: compressed)
        else { return [.welcome] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try current format first
        if let messages = try? decoder.decode([Message].self, from: data), !messages.isEmpty {
            return messages
        }

        // Fallback: legacy format (pre-role model)
        if let legacy = try? decoder.decode([LegacyCodableMessage].self, from: data), !legacy.isEmpty {
            return legacy.map { $0.toMessage() }
        }

        print("[MessageCompressor] Decode failed — starting fresh.")
        return [.welcome]
    }
}

// MARK: - Default welcome message

private extension Message {
    /// The default opening message shown on a fresh day thread.
    static let welcome = Message(
        role: .assistant,
        text: "Hey! How's your day going so far?",
        status: .delivered
    )
}
