import SwiftUI

// MARK: - JourneyAvatar
// The shared circular gradient avatar used throughout the app for
// the AI companion "Journey". Extracted here to prevent duplication.

struct JourneyAvatar: View {
    /// Diameter of the avatar circle.
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [DS.Colors.sage, DS.Colors.dustyBlue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text("J")
                    .font(DS.fontSize(size * 0.38, weight: .medium))
                    .foregroundColor(DS.Colors.onAccent)
            )
    }
}
