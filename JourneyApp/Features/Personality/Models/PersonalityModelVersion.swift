import Foundation

// MARK: - PersonalityModelVersion
// Metadata for one trained model version stored on disk.
// The actual model file lives at Application Support/PersonalityModels/<fileName>.

struct PersonalityModelVersion: Identifiable, Codable, Hashable {
    let id: UUID
    let periodStart: Date
    let periodEnd: Date
    let createdAt: Date
    let fileSizeBytes: Int64
    let parameterCount: Int

    /// Derived filename: e.g. "2025-01-01_2025-01-14.mlpackage"
    var fileName: String {
        "\(DayKey.from(periodStart).rawValue)_\(DayKey.from(periodEnd).rawValue).mlpackage"
    }

    /// Human-readable date range, e.g. "Jan 1 – Jan 14"
    var displayRange: String {
        "\(Self.periodFormatter.string(from: periodStart)) – \(Self.periodFormatter.string(from: periodEnd))"
    }

    private static let periodFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// File size formatted as "X.X MB" or "X KB".
    var formattedSize: String {
        let mb = Double(fileSizeBytes) / 1_048_576
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return "\(fileSizeBytes / 1024) KB"
    }
}

// MARK: - ModelsManifest
// JSON-serializable list persisted at Application Support/PersonalityModels/models_manifest.json.

struct ModelsManifest: Codable {
    var versions: [PersonalityModelVersion]
    var currentVersionId: UUID?
}
