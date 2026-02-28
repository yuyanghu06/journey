import SwiftUI

// MARK: - PersonalityViewModel
// Drives the Past Self simulation chat screen.
// On appear: infers personality tokens from today's conversation and restores any saved session.
// On send: calls /personality/sendMessage with active tokens, then persists both messages.

@MainActor
final class PersonalityViewModel: ObservableObject {

    // MARK: - Published state

    @Published var messages: [PersonalityMessage] = []
    @Published var draft: String = ""
    @Published var activeTokens: [String] = []
    @Published var isPeerTyping: Bool = false
    @Published var isLoadingTokens: Bool = false
    @Published var isAutoTraining: Bool = false
    @Published var isTokenDrawerExpanded: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let modelService: PersonalityModelService
    private let conversationRepository: ConversationRepositoryProtocol
    private let repository: PersonalityRepositoryProtocol
    private let apiClient: APIClientProtocol

    private var currentSessionRecord: PersonalitySessionRecord?
    /// Prevents repeated backend fetches for past days within the same session.
    private var pastDaysHydrated = false

    // MARK: - Init

    init(
        modelService: PersonalityModelService = PersonalityModelService(),
        conversationRepository: ConversationRepositoryProtocol = SwiftDataConversationRepository.shared,
        repository: PersonalityRepositoryProtocol = SwiftDataPersonalityRepository.shared,
        apiClient: APIClientProtocol = APIClient.shared
    ) {
        self.modelService           = modelService
        self.conversationRepository = conversationRepository
        self.repository             = repository
        self.apiClient              = apiClient
    }

    // MARK: - Load

    func loadTokensForToday() async {
        isLoadingTokens = true

        // Warm-start the CoreML model BEFORE training so trainNewVersion can use
        // MLUpdateTask on the stock model rather than falling back to RandomWeightEngine.
        await modelService.ensureModelLoaded()

        // Gather messages from SwiftData (persisted across restarts) + hydrate from
        // backend if the local DB has no user messages yet (first-time launch).
        let inferMessages = await gatherInferenceMessages()

        // Auto-train if no model version exists yet and we have data to train on
        let existingVersions = await modelService.listVersions()
        if existingVersions.isEmpty {
            await autoTrainIfNeeded(using: inferMessages)
        }

        let tokens = (try? await modelService.infer(currentDayMessages: inferMessages)) ?? PersonalityVocabulary.randomSample(k: 8)
        activeTokens    = tokens
        isLoadingTokens = false

        // Restore persisted personality session, or seed welcome message if starting fresh
        if messages.isEmpty {
            let sessions = await repository.fetchSessions()
            if let latest = sessions.first, !latest.messages.isEmpty {
                currentSessionRecord = latest
                messages = latest.messages
                    .sorted { $0.timestamp < $1.timestamp }
                    .map { $0.toPersonalityMessage() }
            } else {
                let versions = await modelService.listVersions()
                let range    = versions.first?.displayRange ?? "recent"
                messages.append(PersonalityMessage(
                    role:         .pastSelf,
                    text:         "Hey! What's new?",
                    activeTokens: tokens
                ))
            }
        }
    }

    // MARK: - Auto-training

    private func autoTrainIfNeeded(using inferMessages: [Message] = []) async {
        // Use the already-gathered messages to avoid a second round-trip
        let allMessages = inferMessages.isEmpty
            ? await { () async -> [Message] in
                let dayKeys = await conversationRepository.listDaysWithConversations()
                var all: [Message] = []
                for key in dayKeys {
                    let conv = await conversationRepository.fetchConversation(dayKey: key)
                    all.append(contentsOf: conv.messages)
                }
                return all
              }()
            : inferMessages

        let userMessages = allMessages.filter { $0.role == .user }
        guard !userMessages.isEmpty else {
            print("[PersonalityModel] autoTrain — no user messages found, skipping")
            return
        }

        isAutoTraining = true
        print("[PersonalityModel] autoTrain — starting first-time training on \(userMessages.count) user messages")

        // Group back into DayConversation wrappers for the training API
        let byDay = Dictionary(grouping: allMessages, by: { $0.dayKey.rawValue })
        let conversations = byDay.map { key, msgs in
            DayConversation(dayKey: DayKey(key), messages: msgs.sorted { $0.timestamp < $1.timestamp })
        }

        let memories = await repository.fetchContextDocuments()

        do {
            _ = try await modelService.trainNewVersion(using: conversations, memories: memories)
            print("[PersonalityModel] autoTrain — complete")
        } catch {
            print("[PersonalityModel] autoTrain — failed: \(error)")
        }
        isAutoTraining = false
    }

    // MARK: - Send

    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPeerTyping else { return }
        draft = ""

        let userMsg = PersonalityMessage(role: .user, text: trimmed, activeTokens: activeTokens)
        messages.append(userMsg)
        isPeerTyping = true

        Task {
            // Re-infer personality tokens BEFORE posting so each message reflects
            // the latest journal conversation state, not the stale tokens from load time.
            let inferMessages = await gatherInferenceMessages()
            let freshTokens   = (try? await modelService.infer(currentDayMessages: inferMessages)) ?? activeTokens
            print("[PersonalityModel] send() — re-inferred tokens: \(freshTokens)")
            activeTokens = freshTokens

            let replyText = await sendToBackend(userText: trimmed, tokens: freshTokens)
            isPeerTyping  = false
            let reply = PersonalityMessage(role: .pastSelf, text: replyText, activeTokens: freshTokens)
            messages.append(reply)
            await persistMessages(user: userMsg, reply: reply)
        }
    }

    // MARK: - Inference message gathering

    /// Returns messages to embed for inference.
    /// Prefers today's user messages; fetches past 14 days from backend if local store is empty.
    private func gatherInferenceMessages() async -> [Message] {
        // 1. Today first
        let today     = await conversationRepository.fetchConversation(dayKey: .today)
        let todayUser = today.messages.filter { $0.role == .user }
        if !todayUser.isEmpty {
            print("[PersonalityModel] gatherInferenceMessages — \(todayUser.count) user msgs from today")
            return today.messages
        }

        // 2. Hydrate past days from backend once per session
        if !pastDaysHydrated {
            await hydratePastDaysFromBackend()
        }

        // 3. Aggregate from recent days (newest first, stop once we have 10+ user messages)
        let allDays = await conversationRepository.listDaysWithConversations()
        var result: [Message] = []
        for dayKey in allDays.sorted().reversed() {
            guard dayKey != .today else { continue }
            let conv = await conversationRepository.fetchConversation(dayKey: dayKey)
            result.append(contentsOf: conv.messages)
            if result.filter({ $0.role == .user }).count >= 10 { break }
        }
        let userCount = result.filter { $0.role == .user }.count
        print("[PersonalityModel] gatherInferenceMessages — no msgs today; using \(userCount) user msgs from recent days")
        return result
    }

    /// Fetches the last 14 days from the backend and writes them into the shared conversation repository.
    /// Called once per session when local data has no user messages.
    private func hydratePastDaysFromBackend() async {
        pastDaysHydrated = true
        let calendar = Calendar.current
        let today    = Date()
        print("[PersonalityModel] hydratePastDays — fetching last 14 days from backend")
        var fetched  = 0
        for offset in 1...14 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = DayKey.from(date)
            do {
                let response = try await apiClient.get(
                    "/days/\(dayKey.rawValue)",
                    responseType: DayDataResponse.self
                )
                let messages = response.conversation.messages.map { $0.toMessage() }
                guard !messages.isEmpty else { continue }
                await conversationRepository.setMessages(messages, dayKey: dayKey)
                fetched += 1
            } catch {
                // 404 = no data for that day — expected, not an error
                if let httpErr = error as? HTTPError, httpErr.status == 404 { continue }
                print("[PersonalityModel] hydratePastDays — error fetching \(dayKey.rawValue): \(error)")
            }
        }
        print("[PersonalityModel] hydratePastDays — loaded \(fetched) past days into local repo")
    }

    // MARK: - Backend call

    private func sendToBackend(userText: String, tokens: [String]) async -> String {
        let history  = await gatherHistoryForBackend()
        let memories = await repository.fetchContextDocuments()

        let historyDTOs = history.map {
            PersonalityHistoryMessageDTO(dayKey: $0.dayKey.rawValue, role: $0.role.rawValue, text: $0.text)
        }
        let req = PersonalitySendMessageRequest(
            dayKey:              DayKey.today.rawValue,
            userText:            userText,
            personalityTokens:   tokens,
            clientMessageId:     UUID().uuidString,
            conversationHistory: historyDTOs,
            memories:            memories.map(\.rawText)
        )
        let response = try? await apiClient.post(
            "/personality/sendMessage",
            body: req,
            responseType: PersonalitySendMessageResponse.self
        )
        return response?.assistantMessage.text ?? "…I'm thinking about how to answer that."
    }

    /// Returns all messages from the last 14 days for inclusion in the backend request.
    private func gatherHistoryForBackend() async -> [Message] {
        if !pastDaysHydrated { await hydratePastDaysFromBackend() }
        let cutoff    = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let cutoffKey = DayKey.from(cutoff)
        let allDays   = await conversationRepository.listDaysWithConversations()
        var result: [Message] = []
        for dayKey in allDays.sorted() where dayKey >= cutoffKey {
            let conv = await conversationRepository.fetchConversation(dayKey: dayKey)
            result.append(contentsOf: conv.messages)
        }
        print("[PersonalityModel] gatherHistoryForBackend — \(result.count) messages across \(allDays.count) days")
        return result
    }

    // MARK: - Persistence

    private func persistMessages(user: PersonalityMessage, reply: PersonalityMessage) async {
        if currentSessionRecord == nil {
            let record = PersonalitySessionRecord()
            await repository.saveSession(record)
            currentSessionRecord = record
        }
        guard let record = currentSessionRecord else { return }
        let userRec  = PersonalityMessageRecord(
            id: user.id,  role: user.role.rawValue,
            text: user.text,  timestamp: user.timestamp,  activeTokens: user.activeTokens)
        let replyRec = PersonalityMessageRecord(
            id: reply.id, role: reply.role.rawValue,
            text: reply.text, timestamp: reply.timestamp, activeTokens: reply.activeTokens)
        record.messages.append(userRec)
        record.messages.append(replyRec)
        await repository.saveSession(record)
    }
}
