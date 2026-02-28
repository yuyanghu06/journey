import SwiftUI
import Combine

// MARK: - UploadContextViewModel
// Drives the context ingestion UI: typed notes and file imports.

@MainActor
final class UploadContextViewModel: ObservableObject {

    // MARK: - Published state

    @Published var noteText: String = ""
    @Published var noteTitle: String = ""
    @Published var isSaving: Bool = false
    @Published var isImporting: Bool = false
    @Published var importError: String?
    @Published var successMessage: String?
    /// Mirrors `documentService.documents` so the view re-renders on changes.
    @Published private(set) var documents: [ContextDocument] = []

    // MARK: - Dependencies

    let documentService: ContextDocumentService

    init(documentService: ContextDocumentService? = nil) {
        let service = documentService ?? ContextDocumentService()
        self.documentService = service
        // Forward the service's @Published array into this ViewModel so SwiftUI
        // picks up changes through a single observed object.
        service.$documents.assign(to: &$documents)
    }

    // MARK: - Save typed note

    func saveNote() async {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSaving = true
        await documentService.saveTextNote(title: noteTitle, text: text)
        noteText       = ""
        noteTitle      = ""
        successMessage = "Note saved."
        isSaving       = false
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        successMessage = nil
    }

    // MARK: - Import file

    func importFile(from url: URL) async {
        isImporting = true
        importError = nil
        let result  = await documentService.importFile(from: url)
        switch result {
        case .success(let doc):
            successMessage = "\"\(doc.title)\" imported (\(doc.characterCount.formatted()) characters)."
            isImporting = false
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            successMessage = nil
        case .failure(let err):
            importError = err.localizedDescription
            isImporting = false
        }
    }

    func deleteDocument(id: UUID) async {
        await documentService.deleteDocument(id: id)
    }
}
