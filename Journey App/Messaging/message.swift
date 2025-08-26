//
//  Message.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//

import Foundation
import SwiftUI

// MARK: - Model
struct Message: Identifiable, Hashable {
    let id: UUID = UUID()
    var text: String
    var isFromCurrentUser: Bool
    var timestamp: Date
    var status: Status = .sent

    enum Status: String {
        case sending, sent, delivered, read
    }
}

// Helper Codable wrapper for Message (since Message already conforms to Hashable/Identifiable but not Codable)
struct CodableMessage: Codable {
    var text: String
    var isFromCurrentUser: Bool
    var timestamp: Date
    var status: String
    
    init(from message: Message) {
        self.text = message.text
        self.isFromCurrentUser = message.isFromCurrentUser
        self.timestamp = message.timestamp
        self.status = message.status.rawValue
    }
    
    func toMessage() -> Message {
        return Message(
            text: text,
            isFromCurrentUser: isFromCurrentUser,
            timestamp: timestamp,
            status: Message.Status(rawValue: status) ?? .sent
        )
    }
}
