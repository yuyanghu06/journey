import SwiftUI

// MARK: - PersonalitySessionView
// The simulation chat UI for "Past Self" conversations.
// Uses blush/lavender bubbles to visually distinguish from the main chat.

struct PersonalitySessionView: View {

    @StateObject private var viewModel = PersonalityViewModel()
    @FocusState  private var inputFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                tokenDrawer
                messageList
                inputBar
            }
            .opacity(viewModel.isAutoTraining ? 0 : 1)
            .disabled(viewModel.isAutoTraining)

            if viewModel.isAutoTraining {
                modelLearningView
            }
        }
        .task { await viewModel.loadTokensForToday() }
    }

    // MARK: - Model Learning Overlay

    private var modelLearningView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            Circle()
                .fill(DS.Colors.softLavender.opacity(0.15))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundColor(DS.Colors.softLavender)
                )

            VStack(spacing: DS.Spacing.sm) {
                Text("Getting to know you…")
                    .font(DS.font(.title3, weight: .medium))
                    .foregroundColor(DS.Colors.primary)

                Text("Past Self is learning from your journal entries for the first time. This only happens once and takes just a moment.")
                    .font(DS.font(.body))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView()
                .tint(DS.Colors.softLavender)
                .scaleEffect(1.2)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.background)
        .transition(.opacity)
    }

    // MARK: - Token Drawer

    private var tokenDrawer: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(DS.Anim.gentle) {
                    viewModel.isTokenDrawerExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.softLavender)

                    if viewModel.isLoadingTokens {
                        Text("Reading your personality…")
                            .font(DS.font(.caption))
                            .foregroundColor(DS.Colors.tertiary)
                    } else {
                        Text(viewModel.activeTokens.prefix(4).joined(separator: " · "))
                            .font(DS.font(.caption))
                            .foregroundColor(DS.Colors.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: viewModel.isTokenDrawerExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(DS.Colors.tertiary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Colors.surface)
            }
            .buttonStyle(.plain)

            if viewModel.isTokenDrawerExpanded {
                expandedTokens
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(DS.Colors.surface.shadow(color: DS.Shadow.color, radius: 4, y: 2))
    }

    private var expandedTokens: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Active personality tokens")
                .font(DS.font(.caption2))
                .foregroundColor(DS.Colors.tertiary)
                .padding(.horizontal, DS.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(viewModel.activeTokens, id: \.self) { token in
                        tokenPill(token)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
            }

            infoNote
                .padding(.horizontal, DS.Spacing.md)
        }
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.backgroundAlt)
    }

    private func tokenPill(_ token: String) -> some View {
        Text(token)
            .font(DS.font(.caption, weight: .medium))
            .foregroundColor(DS.Colors.softLavender)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs + 2)
            .background(DS.Colors.softLavender.opacity(0.15))
            .clipShape(Capsule())
    }

    private var infoNote: some View {
        Label {
            Text("Tokens steer the AI to respond like a past version of you based on your journal history.")
                .font(DS.font(.caption2))
                .foregroundColor(DS.Colors.tertiary)
        } icon: {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.tertiary)
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Spacing.xs) {
                    ForEach(viewModel.messages) { message in
                        PersonalityMessageBubble(message: message)
                            .id(message.id)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xxs)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if viewModel.isPeerTyping {
                        TypingIndicator()
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .transition(.opacity)
                    }

                    Color.clear.frame(height: 8).id("PBOTTOM")
                }
                .padding(.top, DS.Spacing.sm)
            }
            .onAppear { proxy.scrollTo("PBOTTOM", anchor: .bottom) }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(DS.Anim.subtle) { proxy.scrollTo("PBOTTOM", anchor: .bottom) }
            }
            .onChange(of: viewModel.isPeerTyping) { _, _ in
                withAnimation(DS.Anim.subtle) { proxy.scrollTo("PBOTTOM", anchor: .bottom) }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.08)
            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                GrowableTextView(text: $viewModel.draft, placeholder: "Ask your past self…")
                    .focused($inputFocused)
                sendButton
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Colors.surface.ignoresSafeArea(edges: .bottom))
        }
    }

    private var sendButton: some View {
        let canSend = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button(action: viewModel.send) {
            Circle()
                .fill(canSend ? DS.Colors.softLavender : DS.Colors.backgroundAlt)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(canSend ? .white : DS.Colors.tertiary)
                )
                .animation(DS.Anim.fade, value: canSend)
        }
        .disabled(!canSend)
        .buttonStyle(.plain)
    }
}

// MARK: - PersonalityMessageBubble
// Uses blush for user, lavender for past self — distinct from main chat.

private struct PersonalityMessageBubble: View {
    let message: PersonalityMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            if !message.isFromCurrentUser {
                // Past-self avatar: lavender circle
                Circle()
                    .fill(DS.Colors.softLavender.opacity(0.30))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(DS.Colors.softLavender)
                    )
            }

            Text(message.text)
                .font(DS.font(.body))
                .foregroundColor(DS.Colors.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(message.isFromCurrentUser ? DS.Colors.blush : DS.Colors.softLavender.opacity(0.22))
                .clipShape(BubbleShape(isFromCurrentUser: message.isFromCurrentUser))
                .frame(
                    maxWidth: (UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.screen.bounds.width ?? 390) * 0.72,
                    alignment: message.isFromCurrentUser ? .trailing : .leading
                )
        }
        .frame(maxWidth: .infinity, alignment: message.isFromCurrentUser ? .trailing : .leading)
    }
}
