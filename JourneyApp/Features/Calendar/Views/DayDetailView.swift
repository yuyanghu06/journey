import SwiftUI

// MARK: - DayDetailView
// Shows the journal entry and conversation log for a selected day.
// If no journal entry exists, offers a "Generate" CTA.
// If a journal entry exists, offers a "Regenerate" option.

struct DayDetailView: View {
    let date: Date

    @StateObject private var viewModel: DayDetailViewModel

    init(date: Date) {
        self.date = date
        _viewModel = StateObject(
            wrappedValue: DayDetailViewModel(dayKey: DayKey.from(date))
        )
    }

    var body: some View {
        ZStack {
            JourneyBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    dateHeader
                    journalSection
                    conversationSection
                    Spacer(minLength: DS.Spacing.xxl)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.sm)
            }
        }
        .navigationTitle("Day")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadData() }
    }

    // MARK: - Date header

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(viewModel.dayKey.displayString)
                .font(DS.fontSize(22, weight: .semibold))
                .foregroundColor(DS.Colors.primary)
            Text(viewModel.dayKey.rawValue)
                .font(DS.font(.caption))
                .foregroundColor(DS.Colors.tertiary)
        }
    }

    // MARK: - Journal section

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Section header
            HStack {
                Image(systemName: "book.pages")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(DS.Colors.sage)
                Text("Journal Entry")
                    .font(DS.font(.subheadline, weight: .medium))
                    .foregroundColor(DS.Colors.secondary)
                Spacer()

                // Regenerate button — only shown when an entry already exists
                if viewModel.journalEntry != nil && !viewModel.isGeneratingJournal {
                    Button {
                        Task { await viewModel.generateJournalEntry() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(DS.Colors.sage)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Journal body
            journalBody
        }
        .journeyCard(radius: DS.Radius.xl, padding: DS.Spacing.md)
    }

    @ViewBuilder
    private var journalBody: some View {
        if viewModel.isLoadingJournal || viewModel.isGeneratingJournal {
            // Loading / generating spinner
            HStack {
                Spacer()
                VStack(spacing: DS.Spacing.sm) {
                    ProgressView().tint(DS.Colors.sage)
                    if viewModel.isGeneratingJournal {
                        Text("Writing your journal…")
                            .font(DS.font(.caption))
                            .foregroundColor(DS.Colors.tertiary)
                    }
                }
                .padding(.vertical, DS.Spacing.lg)
                Spacer()
            }
        } else if let entry = viewModel.journalEntry {
            // Render the journal text
            Text(entry.text)
                .font(DS.fontSize(16))
                .foregroundColor(DS.Colors.primary)
                .lineSpacing(5)
        } else {
            // No entry yet — show a generate CTA
            VStack(spacing: DS.Spacing.sm) {
                if let errorMsg = viewModel.errorMessage {
                    Text(errorMsg)
                        .font(DS.font(.caption))
                        .foregroundColor(DS.Colors.error)
                }
                Text("No journal entry yet.")
                    .font(DS.font(.body))
                    .foregroundColor(DS.Colors.tertiary)

                // Show CTA only if there is a conversation to summarise
                if viewModel.conversation != nil {
                    Button {
                        Task { await viewModel.generateJournalEntry() }
                    } label: {
                        Text("Generate Journal Entry")
                            .font(DS.font(.subheadline, weight: .medium))
                            .foregroundColor(DS.Colors.onAccent)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical,   DS.Spacing.sm)
                            .background(DS.Colors.sage)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
        }
    }

    // MARK: - Conversation log section

    @ViewBuilder
    private var conversationSection: some View {
        if let conversation = viewModel.conversation, !conversation.messages.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(DS.Colors.dustyBlue)
                    Text("Conversation Log")
                        .font(DS.font(.subheadline, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                    Spacer()
                }

                LazyVStack(spacing: DS.Spacing.xxs) {
                    ForEach(conversation.messages) { message in
                        MessageRow(message: message)
                            .padding(.vertical, DS.Spacing.xxs)
                    }
                }
            }
            .journeyCard(radius: DS.Radius.xl, padding: DS.Spacing.md)
        }
    }
}
