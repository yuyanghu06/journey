import SwiftUI

// MARK: - ChatViewModel

/// Drives all state for the chat screen.
/// Responsibilities:
///   - Loading today's conversation from the repository on init
///   - Appending user messages immediately for a responsive feel
///   - Requesting assistant replies through ChatService
///   - Persisting every message through ConversationRepository
///   - Triggering journal generation when the app backgrounds
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published state

    @Published var messages: [Message] = []
    @Published var draft: String = ""
    @Published var isPeerTyping: Bool = false
    @Published var isLoadingHistory: Bool = true
    @Published var errorMessage: String?

    // MARK: - Public data

    let dayKey: DayKey = .today

    // MARK: - Dependencies

    private let chatService: ChatServiceProtocol
    private let conversationRepository: ConversationRepositoryProtocol
    private let journalRepository: JournalRepositoryProtocol

    // MARK: - Init

    init(
        chatService: ChatServiceProtocol = ChatService(),
        conversationRepository: ConversationRepositoryProtocol = InMemoryConversationRepository(),
        journalRepository: JournalRepositoryProtocol = InMemoryJournalRepository()
    ) {
        self.chatService             = chatService
        self.conversationRepository  = conversationRepository
        self.journalRepository       = journalRepository
        loadTodayConversation()
    }

    // MARK: - Load

    /// Fetches persisted messages for today from the repository.
    /// If the day is fresh, seeds the thread with the assistant's opening line.
    private func loadTodayConversation() {
        isLoadingHistory = true
        Task {
            let conversation = await conversationRepository.fetchConversation(dayKey: dayKey)
            if conversation.messages.isEmpty {
                let welcome = Message(
                    dayKey: dayKey,
                    role: .assistant,
                    text: "Hey! How's your day going so far?",
                    status: .delivered
                )
                await conversationRepository.appendMessage(welcome, dayKey: dayKey)
                messages = [welcome]
            } else {
                messages = conversation.messages
            }
            isLoadingHistory = false
        }
    }

    // MARK: - Send

    /// Called when the user taps the send button.
    /// Appends the user message immediately, then fetches the assistant reply.
    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPeerTyping else { return }

        draft = ""

        let userMsg = Message(dayKey: dayKey, role: .user, text: trimmed, status: .sending)
        messages.append(userMsg)

        // Persist the user message right away
        Task { await conversationRepository.appendMessage(userMsg, dayKey: dayKey) }

        // Animate delivery status ticks in the background
        simulateDelivery(id: userMsg.id)

        // Fetch the assistant reply
        isPeerTyping = true
        let history  = messages
        Task {
            let replyText = await chatService.sendMessage(
                dayKey: dayKey,
                userText: trimmed,
                priorMessages: history
            )
            isPeerTyping = false
            let assistantMsg = Message(dayKey: dayKey, role: .assistant, text: replyText, status: .delivered)
            messages.append(assistantMsg)
            await conversationRepository.appendMessage(assistantMsg, dayKey: dayKey)
        }
    }

    // MARK: - Save & Journal

    /// Called when the app enters the background.
    /// Generates a journal entry for today and upserts it into the journal repository.
    func saveConversationAndGenerateJournal() async {
        guard messages.count > 1 else { return }
        let entryText = await chatService.generateJournalEntry(dayKey: dayKey, messages: messages)
        guard !entryText.isEmpty else { return }
        let entry = JournalEntry(dayKey: dayKey, text: entryText)
        await journalRepository.upsertJournalEntry(entry)
    }

    // MARK: - Private helpers

    /// Simulates the sending → sent → delivered → read status progression
    /// so the UI reflects a realistic messaging feel.
    private func simulateDelivery(id: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            updateStatus(id: id, status: .sent)
            try? await Task.sleep(nanoseconds: 450_000_000)
            updateStatus(id: id, status: .delivered)
            try? await Task.sleep(nanoseconds: 600_000_000)
            updateStatus(id: id, status: .read)
        }
    }

    /// Mutates a message's status in place by its UUID.
    private func updateStatus(id: UUID, status: Message.Status) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].status = status
        }
    }
}
