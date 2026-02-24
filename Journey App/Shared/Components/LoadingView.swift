import SwiftUI

// MARK: - LoadingView
// Full-screen loading splash shown while the app resolves auth state
// or fetches initial data.

struct LoadingView: View {
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.9

    var body: some View {
        ZStack {
            JourneyBackground()

            VStack(spacing: DS.Spacing.md) {
                // App logo avatar
                JourneyAvatar(size: 76)
                    .shadow(color: DS.Shadow.color, radius: DS.Shadow.radius, y: DS.Shadow.y)

                Text("Journey")
                    .font(DS.fontSize(22, weight: .medium))
                    .foregroundColor(DS.Colors.primary)
            }
            .opacity(opacity)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(DS.Anim.gentle) {
                    opacity = 1
                    scale  = 1
                }
            }
        }
    }
}
