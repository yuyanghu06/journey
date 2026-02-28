import SwiftUI

// MARK: - RootView
// The root router — resolves whether to show the loading splash,
// the auth flow, or the main chat screen based on auth state.

struct RootView: View {
    @StateObject private var auth = AuthService()
    @State private var isRefreshing = true

    var body: some View {
        Group {
            if isRefreshing {
                LoadingView()
                    .task {
                        // Attempt a silent token refresh; log out on failure
                        do {
                            try await auth.refreshTokens()
                        } catch {
                            await auth.logout()
                        }
                        withAnimation(DS.Anim.subtle) {
                            isRefreshing = false
                        }
                    }
            } else if auth.isAuthenticated {
                MainTabView()
                    .environmentObject(auth)
                    .onAppear { auth.startTokenRefresher() }
            } else {
                AuthLandingView()
                    .environmentObject(auth)
            }
        }
        .animation(DS.Anim.subtle, value: isRefreshing)
        .animation(DS.Anim.subtle, value: auth.isAuthenticated)
    }
}
