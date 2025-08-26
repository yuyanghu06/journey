import SwiftUI

struct RootView: View {
    @StateObject var auth = AuthService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.isAuthenticated {
                ChatView(auth: auth) // your existing view
                    .environmentObject(auth) // for header logout button later
            } else {
                AuthLandingView()
                    .environmentObject(auth)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background, auth.isAuthenticated {
                NotificationCenter.default.post(name: Notification.Name("SummarizeAndPostOnBackground"), object: nil)
            }
        }
    }
    
    
    
}
