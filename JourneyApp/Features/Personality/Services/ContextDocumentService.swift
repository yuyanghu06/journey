import Foundation
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// MARK: - ContextDocumentService
// Manages user-uploaded context documents that feed into personality training.

@MainActor
final class ContextDocumentService: ObservableObject {

    @Published private(set) var documents: [ContextDocument] = []

    private let repository: PersonalityRepositoryProtocol

    init(repository: PersonalityRepositoryProtocol = SwiftDataPersonalityRepository.shared) {
        self.repository = repository
        Task { await loadDocuments() }
    }

    // MARK: - Load

    func loadDocuments() async {
        documents = await repository.fetchContextDocuments()
    }

    // MARK: - Save plain text

    func saveTextNote(title: String, text: String) async {
        let doc = ContextDocument(title: title.isEmpty ? "Note" : title, rawText: text)
        await repository.saveContextDocument(doc)
        await loadDocuments()
    }

    // MARK: - Import from URL (PDF or TXT)

    func importFile(from url: URL) async -> Result<ContextDocument, ImportError> {
        guard url.startAccessingSecurityScopedResource() else {
            return .failure(.accessDenied)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let ext = url.pathExtension.lowercased()
        let rawText: String

        if ext == "pdf" {
            let pdfText: String? = await Task.detached(priority: .userInitiated) {
                PDFDocument(url: url)?.string
            }.value
            guard let extracted = pdfText, !extracted.isEmpty else {
                return .failure(.extractionFailed("Could not read PDF text"))
            }
            rawText = extracted
        } else {
            let fileText: String? = await Task.detached(priority: .userInitiated) {
                try? String(contentsOf: url, encoding: .utf8)
            }.value
            guard let text = fileText else {
                return .failure(.extractionFailed("Could not read file as UTF-8 text"))
            }
            rawText = text
        }

        let doc = ContextDocument(
            title: url.deletingPathExtension().lastPathComponent,
            rawText: rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        await repository.saveContextDocument(doc)
        await loadDocuments()
        return .success(doc)
    }

    // MARK: - Delete

    func deleteDocument(id: UUID) async {
        await repository.deleteContextDocument(id)
        await loadDocuments()
    }

    // MARK: - Error

    enum ImportError: LocalizedError {
        case accessDenied
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:              return "Could not access the selected file."
            case .extractionFailed(let msg): return msg
            }
        }
    }
}
