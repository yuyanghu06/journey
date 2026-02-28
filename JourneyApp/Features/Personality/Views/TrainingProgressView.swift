import SwiftUI

// MARK: - TrainingProgressView
// A sheet shown during foreground training runs.
// Non-blocking — user can dismiss and training continues.

struct TrainingProgressView: View {

    @ObservedObject var scheduler: PersonalityTrainingScheduler
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.xl) {
                Spacer()

                // Icon
                Circle()
                    .fill(DS.Colors.softLavender.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundColor(DS.Colors.softLavender)
                    )

                // Title + subtitle
                VStack(spacing: DS.Spacing.sm) {
                    Text("Personalizing Journey")
                        .font(DS.fontSize(20, weight: .semibold))
                        .foregroundColor(DS.Colors.primary)

                    Text(scheduler.trainingStatusText.isEmpty
                         ? "Analyzing your conversations…"
                         : scheduler.trainingStatusText)
                        .font(DS.font(.body))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                }

                // Progress bar
                progressBar

                // Error state
                if let err = scheduler.lastError {
                    Text(err)
                        .font(DS.font(.caption))
                        .foregroundColor(DS.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.md)
                }

                // Buttons
                VStack(spacing: DS.Spacing.sm) {
                    if scheduler.isTraining {
                        Button {
                            PersonalityTrainingScheduler.scheduleBackgroundTraining()
                            dismiss()
                        } label: {
                            Text("Run in Background")
                                .font(DS.font(.subheadline, weight: .medium))
                                .foregroundColor(DS.Colors.softLavender)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(DS.font(.subheadline, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, DS.Spacing.xl)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(DS.Colors.softLavender)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.xl)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        VStack(spacing: DS.Spacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                        .fill(DS.Colors.softLavender.opacity(0.15))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                        .fill(DS.Colors.softLavender)
                        .frame(width: geo.size.width * scheduler.trainingProgress, height: 8)
                        .animation(DS.Anim.gentle, value: scheduler.trainingProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Spacer()
                Text("\(Int(scheduler.trainingProgress * 100))%")
                    .font(DS.font(.caption))
                    .foregroundColor(DS.Colors.tertiary)
            }
        }
    }
}
