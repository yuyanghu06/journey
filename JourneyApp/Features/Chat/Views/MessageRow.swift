import SwiftUI

// MARK: - MessageRow
// Renders a single chat message bubble, aligned left for the assistant
// and right for the user. Uses BubbleShape for the chat tail effect.

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
            // Avatar shown only for assistant messages
            if !message.isFromCurrentUser {
                JourneyAvatar(size: 28)
            }

            VStack(
                alignment: message.isFromCurrentUser ? .trailing : .leading,
                spacing: DS.Spacing.xxs
            ) {
                bubble
                statusLabel
            }

            if message.isFromCurrentUser {
                Spacer().frame(width: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isFromCurrentUser ? .trailing : .leading)
    }

    // MARK: - Bubble

    private var bubble: some View {
        Text(message.text)
            .font(DS.font(.body))
            .foregroundColor(
                message.isFromCurrentUser ? DS.Colors.onAccent : DS.Colors.primary
            )
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                message.isFromCurrentUser ? DS.Colors.userBubble : DS.Colors.assistantBubble
            )
            .clipShape(BubbleShape(isFromCurrentUser: message.isFromCurrentUser))
            .frame(
                maxWidth: UIScreen.main.bounds.width * 0.72,
                alignment: message.isFromCurrentUser ? .trailing : .leading
            )
    }

    // MARK: - Status / timestamp label

    private var statusLabel: some View {
        Group {
            if message.isFromCurrentUser {
                // Show delivery tick status for user messages
                Text(message.status.rawValue.capitalized)
                    .font(DS.font(.caption2))
                    .foregroundColor(DS.Colors.tertiary)
            } else {
                // Show send time for assistant messages
                Text(shortTime(message.timestamp))
                    .font(DS.font(.caption2))
                    .foregroundColor(DS.Colors.tertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    /// Formats a Date to a short time string, e.g. "2:34 PM".
    private func shortTime(_ date: Date) -> String {
        MessageRow.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
