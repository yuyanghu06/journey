import Foundation
import BackgroundTasks

// MARK: - PersonalityTrainingScheduler
// Checks on every app foreground whether it's time to train a new model version.
// Fires automatically every 14 days when autoTrainEnabled is true.
// Also registers a BGProcessingTask for long background training runs.

@MainActor
final class PersonalityTrainingScheduler: ObservableObject {

    // MARK: - BGTask identifier
    static let bgTaskIdentifier = "com.journey.personality.train"

    // MARK: - UserDefaults keys
    private enum Keys {
        static let lastTrainingDate  = "personality.lastTrainingDate"
        static let autoTrainEnabled  = "personality.autoTrainEnabled"
    }

    // MARK: - Published state

    @Published var isTraining: Bool = false
    @Published var trainingProgress: Double = 0
    @Published var trainingStatusText: String = ""
    @Published var lastError: String?

    // MARK: - Dependencies

    private let modelService: PersonalityModelService
    private let conversationRepository: ConversationRepositoryProtocol
    private let personalityRepository: PersonalityRepositoryProtocol

    // MARK: - Settings

    var autoTrainEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoTrainEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoTrainEnabled) }
    }

    var lastTrainingDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastTrainingDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastTrainingDate) }
    }

    var daysSinceLastTraining: Int? {
        guard let last = lastTrainingDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    var shouldTrain: Bool {
        guard autoTrainEnabled else { return false }
        guard let days = daysSinceLastTraining else { return true }  // never trained
        return days >= 14
    }

    // MARK: - Init

    init(
        modelService: PersonalityModelService = PersonalityModelService(),
        conversationRepository: ConversationRepositoryProtocol = SwiftDataConversationRepository.shared,
        personalityRepository: PersonalityRepositoryProtocol = SwiftDataPersonalityRepository.shared
    ) {
        self.modelService           = modelService
        self.conversationRepository = conversationRepository
        self.personalityRepository  = personalityRepository
    }

    // MARK: - Check on foreground

    /// Call this every time the app comes to the foreground.
    func checkAndTrainIfNeeded() {
        guard shouldTrain, !isTraining else { return }
        Task { await trainForeground() }
    }

    // MARK: - Foreground training

    func trainForeground() async {
        isTraining      = true
        trainingProgress = 0
        trainingStatusText = "Gathering your recent conversations…"
        lastError        = nil

        do {
            let dayKeys  = await conversationRepository.listDaysWithConversations()
            let cutoff   = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            let recent   = dayKeys.filter { DayKey.from(cutoff) <= $0 }

            trainingProgress   = 0.20
            trainingStatusText = "Building your personality model…"

            var conversations: [DayConversation] = []
            for key in recent {
                let conv = await conversationRepository.fetchConversation(dayKey: key)
                if !conv.messages.isEmpty { conversations.append(conv) }
            }

            trainingProgress   = 0.50
            trainingStatusText = "Training on \(conversations.count) days of conversations…"

            let memories = await personalityRepository.fetchContextDocuments()
            _ = try await modelService.trainNewVersion(using: conversations, memories: memories)

            trainingProgress   = 1.0
            trainingStatusText = "Done!"
            lastTrainingDate   = Date()

        } catch {
            trainingProgress = 0
            lastError        = error.localizedDescription
        }

        isTraining = false
    }

    // MARK: - Background task registration

    /// Call once at app launch (before the first scene becomes active).
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            Self.handleBackgroundTask(processingTask)
        }
    }

    static func scheduleBackgroundTraining() {
        let request = BGProcessingTaskRequest(identifier: bgTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower       = true
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleBackgroundTask(_ task: BGProcessingTask) {
        // NOTE: Background training requires a real, persisted ConversationRepositoryProtocol.
        // Until a shared repository is wired through a dependency container, background
        // training is intentionally a no-op — it will find zero conversations and exit cleanly.
        let trainingTask = Task { @MainActor in
            let scheduler = PersonalityTrainingScheduler()
            await scheduler.trainForeground()
            task.setTaskCompleted(success: scheduler.lastError == nil)
            scheduleBackgroundTraining()
        }
        task.expirationHandler = { trainingTask.cancel() }
    }
}
