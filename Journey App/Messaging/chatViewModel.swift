//
//  chatViewModel.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//

import SwiftUI
import Foundation

// MARK: - ViewModel

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var summary: String = "No summary available."
    @Published var draft: String = ""
    @Published var isPeerTyping: Bool = false
    @Published var messageLoading: Bool = false
    
    private let auth: AuthService
    
    init(auth: AuthService) {
        self.auth = auth
        self.messageLoading = true
        let today = isoDateString()
        // Load message history for today
        Task {
            do {
                let history = try await auth.getCompressedHistory(for: today) ?? ""
                DispatchQueue.main.async {
                    self.messages = decompressMessages(history)
                    self.messageLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    // Fallback: stop loading and show a lightweight placeholder
                    self.messageLoading = false
                    self.messages = [
                        Message(text: "Hey there! How's it going today?", isFromCurrentUser: false, timestamp: Date(), status: .delivered)
                    ]
                }
            }
        }
    }

    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var msg = Message(text: trimmed, isFromCurrentUser: true, timestamp: Date(), status: .sending)
        messages.append(msg)
        draft = ""

        // Simulate a network lifecycle for the status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let idx = self.messages.lastIndex(where: { $0.id == msg.id }) {
                self.messages[idx].status = .sent
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let idx = self.messages.lastIndex(where: { $0.id == msg.id }) {
                self.messages[idx].status = .delivered
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let idx = self.messages.lastIndex(where: { $0.id == msg.id }) {
                self.messages[idx].status = .read
            }
        }

        // Send to OpenAI instead of local auto-responder
        isPeerTyping = true
        messageGPT(trimmed) { response in
            self.isPeerTyping = false
            let assistantText = response ?? "Sorry — I couldn't get a reply right now."
            self.messages.append(
                Message(text: assistantText, isFromCurrentUser: false, timestamp: Date(), status: .delivered)
            )
        }
    }
}
