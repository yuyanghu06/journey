import SwiftUI

struct RootView: View {
    @StateObject var auth = AuthService()
    @State private var isRefreshing = true   // new state

    var body: some View {
        Group {
            if isRefreshing {
                ProgressView("Refreshing session...") // loading placeholder
                    .task {
                        do {
                            try await auth.refreshTokens()
                        } catch {
                            await auth.logout()
                        }
                        isRefreshing = false
                    }
            } else if auth.isAuthenticated {
                ChatView(auth: auth)
                    .environmentObject(auth)
            } else {
                AuthLandingView()
                    .environmentObject(auth)
            }
        }
    }
}
