import SwiftUI
import SwiftData

@main
struct Journey_AppApp: App {

    init() {
        PersonalityTrainingScheduler.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppModelContainer.shared)
    }
}
