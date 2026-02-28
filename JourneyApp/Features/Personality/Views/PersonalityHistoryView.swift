import SwiftUI

// MARK: - PersonalityHistoryView
// Lists stored model versions, offers training trigger and delete actions.

struct PersonalityHistoryView: View {

    @StateObject private var viewModel = PersonalityHistoryViewModel()

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            if viewModel.versions.isEmpty {
                emptyState
            } else {
                versionList
            }
        }
        .onAppear { viewModel.loadVersions() }
        .sheet(isPresented: $viewModel.showTrainingSheet) {
            TrainingProgressView(scheduler: viewModel.trainingScheduler)
        }
        .confirmationDialog(
            "Delete all personality models?",
            isPresented: $viewModel.showDeleteAllAlert,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { viewModel.deleteAllVersions() }
        } message: {
            Text("This cannot be undone. All conversation simulations will stop working until a new model is trained.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(DS.Colors.softLavender.opacity(0.6))

            VStack(spacing: DS.Spacing.sm) {
                Text("No personality models yet")
                    .font(DS.fontSize(17, weight: .medium))
                    .foregroundColor(DS.Colors.primary)
                Text("Your first model will be generated automatically after 14 days of journaling, or you can trigger it manually now.")
                    .font(DS.font(.body))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
            }

            generateButton
        }
        .padding(DS.Spacing.xl)
    }

    // MARK: - Version list

    private var versionList: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sm) {
                generateButton
                    .padding(.top, DS.Spacing.sm)

                ForEach(viewModel.versions) { version in
                    PersonalityVersionRow(version: version) {
                        viewModel.deleteVersion(version)
                    }
                }

                deleteAllButton
                    .padding(.bottom, DS.Spacing.lg)
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - Buttons

    private var generateButton: some View {
        Button {
            viewModel.triggerTraining()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                Text("Generate New Version")
                    .font(DS.font(.subheadline, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Colors.softLavender)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var deleteAllButton: some View {
        Button {
            viewModel.showDeleteAllAlert = true
        } label: {
            Text("Clear All Models")
                .font(DS.font(.subheadline))
                .foregroundColor(DS.Colors.error)
        }
        .buttonStyle(.plain)
        .padding(.top, DS.Spacing.sm)
    }
}
