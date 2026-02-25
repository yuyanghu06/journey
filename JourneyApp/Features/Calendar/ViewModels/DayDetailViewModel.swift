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

    /// Fetches both the journal entry and conversation for the day in parallel.
    func loadData() async {
        isLoadingJournal      = true
        isLoadingConversation = true
        errorMessage          = nil

        async let entry        = journalRepository.fetchJournalEntry(dayKey: dayKey)
        async let conversation = conversationRepository.fetchConversation(dayKey: dayKey)

        let (j, c) = await (entry, conversation)
        journalEntry  = j
        self.conversation = c.messages.isEmpty ? nil : c
        isLoadingJournal      = false
        isLoadingConversation = false
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
