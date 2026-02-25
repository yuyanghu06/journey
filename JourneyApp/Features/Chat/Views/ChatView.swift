import SwiftUI

// MARK: - ChatView
// The home screen — a full-screen messenger that shows today's conversation
// with the Journey AI companion. Mirrors the UX of a modern chat app:
// persistent history, typing indicator, and a pill-shaped input bar.

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState  private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if viewModel.isLoadingHistory {
                LoadingView()
            } else {
                mainContent
            }
        }
        // Save conversation when the app goes to background
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                Task { await viewModel.saveConversationAndGenerateJournal() }
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        NavigationStack {
            ZStack {
                JourneyBackground()

                VStack(spacing: 0) {
                    header
                    messageList
                    inputBar
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.sm) {
            JourneyAvatar(size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Journey")
                    .font(DS.fontSize(16, weight: .semibold))
                    .foregroundColor(DS.Colors.primary)
                Text("Your journaling companion")
                    .font(DS.font(.caption))
                    .foregroundColor(DS.Colors.secondary)
            }

            Spacer()

            // Navigation buttons
            NavigationLink(destination: CalendarView().environmentObject(auth)) {
                headerIconButton(icon: "calendar")
            }
            .buttonStyle(.plain)

            NavigationLink(destination: BugView().environmentObject(auth)) {
                headerIconButton(icon: "ladybug")
            }
            .buttonStyle(.plain)

            Button {
                Task { await auth.logout() }
            } label: {
                headerIconButton(icon: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical,   DS.Spacing.sm)
        .background(DS.Colors.surface.ignoresSafeArea(edges: .top).shadow(color: DS.Shadow.color, radius: 6, y: 2))
    }

    /// Small circular icon button used in the header toolbar.
    private func headerIconButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .light))
            .foregroundColor(DS.Colors.secondary)
            .frame(width: 36, height: 36)
            .background(DS.Colors.backgroundAlt)
            .clipShape(Circle())
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Spacing.xs) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical,   DS.Spacing.xxs)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Typing indicator shown while the assistant is replying
                    if viewModel.isPeerTyping {
                        TypingIndicator()
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical,   DS.Spacing.xs)
                            .transition(.opacity)
                    }

                    // Invisible anchor for auto-scrolling to the bottom
                    Color.clear.frame(height: 8).id("BOTTOM")
                }
                .padding(.top, DS.Spacing.sm)
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: viewModel.messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.isPeerTyping)   { _ in scrollToBottom(proxy) }
        }
    }

    /// Scrolls to the bottom anchor, optionally animated.
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        withAnimation(animated ? DS.Anim.subtle : nil) {
            proxy.scrollTo("BOTTOM", anchor: .bottom)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.08)
            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                GrowableTextView(text: $viewModel.draft, placeholder: "Write something…")
                    .focused($inputFocused)

                sendButton
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical,   DS.Spacing.sm)
            .background(DS.Colors.surface.ignoresSafeArea(edges: .bottom))
        }
    }

    /// The circular send button — filled when there is text to send.
    private var sendButton: some View {
        let canSend = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button(action: viewModel.send) {
            Circle()
                .fill(canSend ? DS.Colors.dustyBlue : DS.Colors.backgroundAlt)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(canSend ? DS.Colors.onAccent : DS.Colors.tertiary)
                )
                .animation(DS.Anim.fade, value: canSend)
        }
        .disabled(!canSend)
        .buttonStyle(.plain)
    }
}
