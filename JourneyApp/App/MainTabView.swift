import SwiftUI

// MARK: - MainTabView
// Root tab container for authenticated users.
// Chat (Today) · Past Self (Personality) · Explore (Calendar)

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        TabView {
            // Tab 0 — Today's chat
            ChatView()
                .tabItem {
                    Label("Today", systemImage: "bubble.left.and.bubble.right")
                }

            // Tab 1 — Past Self personality simulation
            PersonalityTabView()
                .tabItem {
                    Label("Past Self", systemImage: "sparkles")
                }

            // Tab 2 — Calendar / Explore
            NavigationStack {
                CalendarView()
            }
            .environmentObject(auth)
            .tabItem {
                Label("Explore", systemImage: "calendar")
            }
        }
        .tint(DS.Colors.dustyBlue)
        .onAppear { styleTabBar() }
    }

    private func styleTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        // Warm surface background matching Journey design system
        appearance.backgroundColor = UIColor(DS.Colors.surface)
        UITabBar.appearance().standardAppearance  = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
