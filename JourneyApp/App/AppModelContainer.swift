import SwiftData
import Foundation

// MARK: - AppModelContainer
// Single shared ModelContainer for the entire app.
// All SwiftData repositories init their ModelContext from this shared container,
// avoiding duplicate containers and ensuring consistent persistent storage.

enum AppModelContainer {
    static let shared: ModelContainer = {
        let types: [any PersistentModel.Type] = [
            MessageRecord.self,
            ContextDocument.self,
            PersonalitySessionRecord.self,
            PersonalityMessageRecord.self
        ]
        if let container = try? ModelContainer(for: Schema(types)) {
            return container
        }
        // Fallback: in-memory only (e.g. migration failure)
        let memConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let fallback = try? ModelContainer(for: Schema(types), configurations: memConfig) else {
            fatalError("Cannot create ModelContainer")
        }
        return fallback
    }()
}
