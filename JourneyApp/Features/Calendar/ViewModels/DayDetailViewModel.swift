import SwiftUI

// MARK: - DayDetailViewModel
// Loads and manages state for a single day's journal entry and conversation log.

@MainActor
final class DayDetailViewModel: ObservableObject {

    // MARK: - Published state

    @Published var journalEntry: JournalEntry?
    @Published var conversation: DayConversation?
    @Published var isLoadingJournal: Bool = true
    @Published var isLoadingConversation: Bool = true
    @Published var isGeneratingJournal: Bool = false
    @Published var errorMessage: String?

    // MARK: - Public data

    let dayKey: DayKey

    // MARK: - Dependencies

    private let journalRepository: JournalRepositoryProtocol
    private let conversationRepository: ConversationRepositoryProtocol
    private let chatService: ChatServiceProtocol

    // MARK: - Init

    init(
        dayKey: DayKey,
        journalRepository: JournalRepositoryProtocol = InMemoryJournalRepository(),
        conversationRepository: ConversationRepositoryProtocol = InMemoryConversationRepository(),
        chatService: ChatServiceProtocol = ChatService()
    ) {
        self.dayKey                 = dayKey
        self.journalRepository      = journalRepository
        self.conversationRepository = conversationRepository
        self.chatService            = chatService
    }

    // MARK: - Load

    /// Fetches the conversation and journal entry for the day from the backend.
    /// Falls back to local repositories if the backend is unreachable.
    /// Auto-generates a journal entry if the day has messages but no entry yet.
    func loadData() async {
        isLoadingJournal      = true
        isLoadingConversation = true
        errorMessage          = nil

        if let dayData = try? await APIClient.shared.get(
            "/days/\(dayKey.rawValue)",
            responseType: DayDataResponse.self
        ) {
            let msgs = dayData.conversation.messages.map { $0.toMessage() }
            self.conversation = msgs.isEmpty ? nil : DayConversation(dayKey: dayKey, messages: msgs)
            journalEntry      = dayData.journalEntry?.toJournalEntry()
        } else {
            // Fallback: read from local in-memory repositories.
            async let entry = journalRepository.fetchJournalEntry(dayKey: dayKey)
            async let conv  = conversationRepository.fetchConversation(dayKey: dayKey)
            let (j, c) = await (entry, conv)
            journalEntry      = j
            self.conversation = c.messages.isEmpty ? nil : c
        }

        isLoadingJournal      = false
        isLoadingConversation = false

        // Auto-generate a journal entry when the day has messages but no entry yet.
        if journalEntry == nil, self.conversation != nil {
            await generateJournalEntry()
        }
    }

    // MARK: - Generate / Regenerate

    /// Generates (or regenerates) the journal entry for this day via the chat service.
    func generateJournalEntry() async {
        guard let messages = conversation?.messages, !messages.isEmpty else { return }
        isGeneratingJournal = true
        errorMessage        = nil

        let text = await chatService.generateJournalEntry(dayKey: dayKey, messages: messages)

        if text.isEmpty {
            errorMessage = "Couldn't generate a journal entry. Please try again."
        } else {
            let entry = JournalEntry(dayKey: dayKey, text: text)
            await journalRepository.upsertJournalEntry(entry)
            journalEntry = entry
        }
        isGeneratingJournal = false
    }
}
