import SwiftUI
import UniformTypeIdentifiers

// MARK: - UploadContextView
// Lets users feed external text into personality training via typed notes or imported files.

struct UploadContextView: View {

    @StateObject private var viewModel = UploadContextViewModel()
    @State private var showDocumentPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                // Header card
                contextExplainer

                // Type a note
                noteEntryCard

                // Import button
                importCard

                // Saved documents
                if !viewModel.documents.isEmpty {
                    savedDocumentsSection
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.sm)
        }
        .background(DS.Colors.background.ignoresSafeArea())
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                Task { await viewModel.importFile(from: url) }
            }
        }
        .overlay(alignment: .top) {
            if let msg = viewModel.successMessage {
                Text(msg)
                    .font(DS.font(.caption, weight: .medium))
                    .foregroundColor(DS.Colors.onAccent)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Colors.sage)
                    .clipShape(Capsule())
                    .padding(.top, DS.Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DS.Anim.subtle, value: viewModel.successMessage)
    }

    // MARK: - Context explainer

    private var contextExplainer: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "brain")
                .font(.system(size: 20, weight: .ultraLight))
                .foregroundColor(DS.Colors.softLavender)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("External Memory")
                    .font(DS.font(.subheadline, weight: .medium))
                    .foregroundColor(DS.Colors.primary)
                Text("Add notes or documents that enrich your personality model — diaries, letters, personal writing.")
                    .font(DS.font(.caption))
                    .foregroundColor(DS.Colors.secondary)
            }
        }
        .journeyCard(radius: DS.Radius.lg, padding: DS.Spacing.md)
    }

    // MARK: - Note entry

    private var noteEntryCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Write a note")
                .font(DS.font(.subheadline, weight: .medium))
                .foregroundColor(DS.Colors.secondary)

            TextField("Title (optional)", text: $viewModel.noteTitle)
                .font(DS.font(.body))
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Colors.backgroundAlt)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            GrowableTextView(text: $viewModel.noteText, placeholder: "Write freely…")
                .frame(minHeight: 80)

            Button {
                Task { await viewModel.saveNote() }
            } label: {
                HStack {
                    Spacer()
                    Group {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save Note")
                                .font(DS.font(.subheadline, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Colors.softLavender)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)
        }
        .journeyCard(radius: DS.Radius.xl, padding: DS.Spacing.md)
    }

    // MARK: - Import card

    private var importCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button {
                showDocumentPicker = true
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 20, weight: .ultraLight))
                        .foregroundColor(DS.Colors.dustyBlue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import PDF or TXT")
                            .font(DS.font(.subheadline, weight: .medium))
                            .foregroundColor(DS.Colors.primary)
                        Text("Personal writing, diaries, letters")
                            .font(DS.font(.caption))
                            .foregroundColor(DS.Colors.tertiary)
                    }

                    Spacer()

                    if viewModel.isImporting {
                        ProgressView().tint(DS.Colors.dustyBlue)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(DS.Colors.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .journeyCard(radius: DS.Radius.xl, padding: DS.Spacing.md)

            if let err = viewModel.importError {
                Text(err).font(DS.font(.caption)).foregroundColor(DS.Colors.error)
                    .padding(.horizontal, DS.Spacing.xs)
            }
        }
    }

    // MARK: - Saved documents

    private var savedDocumentsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Saved Context")
                .font(DS.font(.subheadline, weight: .medium))
                .foregroundColor(DS.Colors.secondary)
                .padding(.horizontal, DS.Spacing.xxs)

            ForEach(viewModel.documents) { doc in
                contextDocumentRow(doc)
            }
        }
    }

    private func contextDocumentRow(_ doc: ContextDocument) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .ultraLight))
                .foregroundColor(DS.Colors.dustyBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(doc.title)
                    .font(DS.font(.subheadline, weight: .medium))
                    .foregroundColor(DS.Colors.primary)
                Text(doc.preview)
                    .font(DS.font(.caption))
                    .foregroundColor(DS.Colors.tertiary)
                    .lineLimit(2)
                Text("\(doc.characterCount.formatted()) characters · \(formattedDate(doc.createdAt))")
                    .font(DS.font(.caption2))
                    .foregroundColor(DS.Colors.tertiary.opacity(0.7))
            }

            Spacer()

            Button {
                Task { await viewModel.deleteDocument(id: doc.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(DS.Colors.tertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.sm)
        .background(DS.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

// MARK: - DocumentPickerView
// UIKit document picker wrapped for SwiftUI.

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.pdf, .plainText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
