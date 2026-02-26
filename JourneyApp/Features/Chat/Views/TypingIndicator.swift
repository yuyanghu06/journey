import SwiftUI

// MARK: - TypingIndicator
// Animated three-dot indicator shown while the assistant is composing a reply.
// Uses the shared JourneyAvatar and the assistant bubble background colour.

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            JourneyAvatar(size: 28)

            // Three pulsing dots inside a soft bubble
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DS.Colors.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(animating ? 1.0 : 0.35)
                        .animation(
                            DS.Anim.gentle
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18),
                            value: animating
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
        .onAppear { animating = true }
    }
}
