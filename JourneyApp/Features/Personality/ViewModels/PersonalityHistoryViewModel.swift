import SwiftUI

// MARK: - PersonalityHistoryViewModel
// Manages stored model versions and training trigger for PersonalityHistoryView.

@MainActor
final class PersonalityHistoryViewModel: ObservableObject {

    // MARK: - Published state

    @Published var versions: [PersonalityModelVersion] = []
    @Published var showDeleteAllAlert: Bool = false
    @Published var showTrainingSheet: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let modelService: PersonalityModelService
    private let scheduler: PersonalityTrainingScheduler

    /// Exposed for TrainingProgressView which observes the scheduler directly.
    var trainingScheduler: PersonalityTrainingScheduler { scheduler }

    // MARK: - Init

    init(
        modelService: PersonalityModelService,
        scheduler:    PersonalityTrainingScheduler
    ) {
        self.modelService = modelService
        self.scheduler    = scheduler
        loadVersions()
    }

    convenience init() {
        self.init(
            modelService: PersonalityModelService(),
            scheduler:    PersonalityTrainingScheduler()
        )
    }

    // MARK: - Actions

    func loadVersions() {
        Task {
            let v = await modelService.listVersions()
            versions = v
        }
    }

    func triggerTraining() {
        showTrainingSheet = true
        Task {
            await scheduler.trainForeground()
            loadVersions()
        }
    }

    func deleteVersion(_ version: PersonalityModelVersion) {
        Task {
            do {
                try await modelService.deleteVersion(version)
                loadVersions()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteAllVersions() {
        Task {
            do {
                try await modelService.deleteAllVersions()
                loadVersions()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
