import SwiftUI

// MARK: - BugView
// Lets the user compose and submit a bug report.
// Shows a thank-you overlay on successful submission, then auto-dismisses.

struct BugView: View {
    @State private var bugText   = ""
    @State private var isSending = false
    @State private var showThanks = false
    @Environment(\.dismiss) private var dismiss

    private let service: BugReportServiceProtocol

    init(service: BugReportServiceProtocol = BugReportService()) {
        self.service = service
    }

    var body: some View {
        ZStack {
            JourneyBackground()

            if showThanks {
                thanksOverlay
            } else {
                mainForm
            }
        }
        .navigationTitle("Report a Bug")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Main Form

    private var mainForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                // Header copy
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Found something off?")
                        .font(DS.fontSize(20, weight: .semibold))
                        .foregroundColor(DS.Colors.primary)
                    Text("Describe what happened and we'll look into it.")
                        .font(DS.font(.subheadline))
                        .foregroundColor(DS.Colors.secondary)
                }
                .padding(.top, DS.Spacing.sm)

                // Multi-line text card
                textEditorCard

                sendButton
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    private var textEditorCard: some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .topLeading) {
                if bugText.isEmpty {
                    Text("Describe the bug…")
                        .font(DS.font(.body))
                        .foregroundColor(DS.Colors.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $bugText)
                    .font(DS.font(.body))
                    .foregroundColor(DS.Colors.primary)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
            }
        }
        .journeyCard(radius: DS.Radius.lg, padding: DS.Spacing.md)
    }

    private var sendButton: some View {
        let canSend = !bugText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
        return Button {
            guard canSend else { return }
            Task { await submit() }
        } label: {
            Group {
                if isSending {
                    ProgressView().tint(DS.Colors.onAccent)
                } else {
                    Text("Send Report")
                        .font(DS.font(.body, weight: .semibold))
                        .foregroundColor(DS.Colors.onAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(canSend ? DS.Colors.sage : DS.Colors.backgroundAlt)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .animation(DS.Anim.fade, value: canSend)
        }
        .disabled(!canSend)
    }

    // MARK: - Thanks overlay

    private var thanksOverlay: some View {
        VStack(spacing: DS.Spacing.md) {
            Circle()
                .fill(DS.Colors.sage.opacity(0.2))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(DS.Colors.sage)
                )
            Text("Thank you!")
                .font(DS.fontSize(22, weight: .semibold))
                .foregroundColor(DS.Colors.primary)
            Text("Your report has been received.")
                .font(DS.font(.subheadline))
                .foregroundColor(DS.Colors.secondary)
        }
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Submit

    private func submit() async {
        let trimmed = bugText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        do {
            try await service.submitReport(description: trimmed)
            bugText = ""
            withAnimation(DS.Anim.gentle) { showThanks = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            print("[BugView] Submission failed: \(error.localizedDescription)")
        }
        isSending = false
    }
}
