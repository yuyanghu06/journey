import SwiftUI

// MARK: - PersonalityVersionRow
// A single card in PersonalityHistoryView showing one trained model version.

struct PersonalityVersionRow: View {
    let version: PersonalityModelVersion
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            // Date range icon
            Circle()
                .fill(DS.Colors.softLavender.opacity(0.20))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "clock.fill")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(DS.Colors.softLavender)
                )

            // Info
            VStack(alignment: .leading, spacing: DS.Spacing.xxs + 1) {
                Text(version.displayRange)
                    .font(DS.font(.subheadline, weight: .medium))
                    .foregroundColor(DS.Colors.primary)

                HStack(spacing: DS.Spacing.xs) {
                    Text(version.formattedSize)
                    Text("·")
                    Text("\(version.parameterCount.formatted()) params")
                }
                .font(DS.font(.caption2))
                .foregroundColor(DS.Colors.tertiary)
            }

            Spacer()

            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(DS.Colors.error.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.md)
        .background(DS.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(color: DS.Shadow.color, radius: DS.Shadow.radius, y: DS.Shadow.y)
    }
}
