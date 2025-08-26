//
//  compress-decompress.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//
import Foundation

// MARK: - Compression / Decompression
func compressMessages(_ messages: [Message]) -> String? {
    let codableMessages = messages.map { CodableMessage(from: $0) }
    do {
        let data = try JSONEncoder().encode(codableMessages)
        return data.base64EncodedString()
    } catch {
        print("Failed to compress messages: \(error)")
        return nil
    }
}

func decompressMessages(_ compressed: String) -> [Message] {
    if compressed == "" { return [Message(text: "Hey there! How's it going today?", isFromCurrentUser: false, timestamp: Date(), status: .delivered)]}
    guard let data = Data(base64Encoded: compressed) else { return [Message(text: "Hey there! How's it going today?", isFromCurrentUser: false, timestamp: Date(), status: .delivered)] }
    do {
        let codableMessages = try JSONDecoder().decode([CodableMessage].self, from: data)
        return codableMessages.map { $0.toMessage() }
    } catch {
        print("Failed to decompress messages: \(error)")
        return [Message(text: "Hey there! How's it going today?", isFromCurrentUser: false, timestamp: Date(), status: .delivered)]
    }
}
