import SwiftUI

// MARK: - TypingIndicator
// Animated three-dot indicator shown while the assistant is composing a reply.
// Uses the shared JourneyAvatar and the assistant bubble background colour.

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            JourneyAvatar(size: 28)

            // Three pulsing dots inside a soft bubble
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DS.Colors.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(dotOpacity(index: index))
                        .animation(
                            DS.Anim.gentle.repeatForever().delay(Double(index) * 0.18),
                            value: phase
                        )
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(DS.Colors.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))

            Spacer()
        }
        .padding(.leading, DS.Spacing.sm)
        .onAppear { phase = 1 }
    }

    /// Returns a pulsing opacity value for the given dot index.
    private func dotOpacity(index: Int) -> Double {
        let base = Double(phase)
        return 0.35 + 0.65 * abs(sin((base + Double(index) * 0.5) * .pi))
    }
}
