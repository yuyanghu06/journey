import SwiftUI
import Foundation
// MARK: - Model

var currEntry: String = ""

struct Message: Identifiable, Hashable {
    let id: UUID = UUID()
    var text: String
    var isFromCurrentUser: Bool
    var timestamp: Date
    var status: Status = .sent

    enum Status: String {
        case sending, sent, delivered, read
    }
}

// MARK: - ViewModel

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var draft: String = ""
    @Published var isPeerTyping: Bool = false
    
    init() {
        // Seed a few sample messages
        messages = [
           Message(text: "Hey! How's your day going? Wanna tell me about it?", isFromCurrentUser: false, timestamp: Date(), status: .read),
        ]
    }

    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var msg = Message(text: trimmed, isFromCurrentUser: true, timestamp: Date(), status: .sending)
        messages.append(msg)
        draft = ""

        // Simulate a network lifecycle for the status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let idx = self.messages.lastIndex(where: { $0.id == msg.id }) {
                self.messages[idx].status = .sent
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let idx = self.messages.lastIndex(where: { $0.id == msg.id }) {
                self.messages[idx].status = .delivered
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let idx = self.messages.lastIndex(where: { $0.id == msg.id }) {
                self.messages[idx].status = .read
            }
        }

        // Send to OpenAI instead of local auto-responder
        isPeerTyping = true
        messageGPT(trimmed) { response in
            self.isPeerTyping = false
            let assistantText = response ?? "Sorry — I couldn't get a reply right now."
            self.messages.append(
                Message(text: assistantText, isFromCurrentUser: false, timestamp: Date(), status: .delivered)
            )
        }
    }
}


// MARK: - Views

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var focused: Bool
    @State private var goToCalendar = false

    init(viewModel: ChatViewModel = ChatViewModel()) {
        self.viewModel = viewModel
        self._focused = FocusState() // initializes the wrapper
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.2)
                messageList
                inputBar
            }
            .background(
                NavigationLink(destination: CalendarView(), isActive: $goToCalendar) {
                    EmptyView()
                }
                .hidden()
            )
            .background(Color(.systemGroupedBackground))
        }
    }

    var header: some View {
        HStack {
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 36, height: 36)
                .overlay(Text("J").font(.caption).bold())
            VStack(alignment: .leading, spacing: 2) {
                Text("Journey").font(.headline)
                Text("Your personal journaling companion").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            
            Button {
                summarizeGPT(viewModel.messages) { entry in
                    currEntry = entry ?? "No summary available."
                    goToCalendar = true
                }
            } label: {
                Image(systemName: "calendar")
                    .font(.title2)
                    .padding(8)
            }
            .buttonStyle(.plain)
            
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.messages) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                    }
                    if viewModel.isPeerTyping {
                        TypingIndicator()
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                    }
                    Rectangle().fill(Color.clear).frame(height: 4)
                        .id("BOTTOM")
                }
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: viewModel.messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.isPeerTyping) { _ in scrollToBottom(proxy) }
        }
    }

    func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            withAnimation(animated ? .easeOut(duration: 0.25) : nil) {
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
        }
    }

    var inputBar: some View {
        VStack(spacing: 6) {
            Divider().opacity(0.2)
            HStack(alignment: .center, spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)

                GrowableTextView(text: $viewModel.draft, placeholder: "iMessage…")
                    .focused($focused)

                Button(action: viewModel.send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    var message: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.isFromCurrentUser {
            } else {
            }

            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                bubble
                status
            }

            if message.isFromCurrentUser {
                
            } else {
                Spacer().frame(width: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isFromCurrentUser ? .trailing : .leading)
    }

    var avatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 26, height: 26)
            .overlay(Text("A").font(.caption2).bold())
            .padding(.bottom, 2)
    }

    var bubble: some View {
        Text(message.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundColor(message.isFromCurrentUser ? .white : .primary)
            .background(
                message.isFromCurrentUser
                ? Color.blue
                : Color(.systemGray5)
            )
            .clipShape(BubbleShape(isFromCurrentUser: message.isFromCurrentUser))
    }

    var status: some View {
        Group {
            if message.isFromCurrentUser {
                Text(message.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Shapes & Components

struct BubbleShape: Shape {
    let isFromCurrentUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let corners: UIRectCorner = isFromCurrentUser
            ? [.topLeft, .topRight, .bottomRight]
            : [.topLeft, .topRight, .bottomLeft]

        let bez = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        var path = Path(bez.cgPath)

        // Tiny tail
        let tailWidth: CGFloat = 6
        let tailHeight: CGFloat = 10
        let y = rect.maxY - 6

        if isFromCurrentUser {
            var p = Path()
            p.move(to: CGPoint(x: rect.maxX - 10, y: y - tailHeight))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: y),
                           control: CGPoint(x: rect.maxX - 2, y: y - 4))
            p.addLine(to: CGPoint(x: rect.maxX - tailWidth, y: y - 2))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - 10, y: y - tailHeight),
                           control: CGPoint(x: rect.maxX - 8, y: y - 8))
            path.addPath(p)
        } else {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + 10, y: y - tailHeight))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: y),
                           control: CGPoint(x: rect.minX + 2, y: y - 4))
            p.addLine(to: CGPoint(x: rect.minX + tailWidth, y: y - 2))
            p.addQuadCurve(to: CGPoint(x: rect.minX + 10, y: y - tailHeight),
                           control: CGPoint(x: rect.minX + 8, y: y - 8))
            path.addPath(p)
        }
        return path
    }
}

struct GrowableTextView: View {
    @Binding var text: String
    var placeholder: String = ""

    @State private var dynamicHeight: CGFloat = 36

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder).foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.leading, 6)
            }
            TextEditor(text: $text)
                .frame(minHeight: 36, maxHeight: min(max(dynamicHeight, 36), 120))
                .scrollContentBackground(.hidden)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .onChange(of: text) { _ in recalcHeight() }
                .onAppear { recalcHeight() }
        }
    }

    private func recalcHeight() {
        let size = CGSize(width: UIScreen.main.bounds.width - 120, height: .greatestFiniteMagnitude)
        let attributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .body)]
        let bounding = (text as NSString).boundingRect(with: size, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        dynamicHeight = bounding.height + 24
    }
}

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack {
            Circle().fill(Color.gray.opacity(0.25)).frame(width: 26, height: 26)
                .overlay(Text("A").font(.caption2).bold())
            HStack(spacing: 6) {
                Circle().frame(width: 8, height: 8)
                Circle().frame(width: 8, height: 8)
                Circle().frame(width: 8, height: 8)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundColor(.secondary)
            .background(Color(.secondarySystemBackground))
            .clipShape(BubbleShape(isFromCurrentUser: false))
            .modifier(PulsingDots(phase: phase))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
            Spacer()
        }
        .padding(.leading, 8)
        .padding(.top, 2)
    }
}

struct PulsingDots: ViewModifier {
    var phase: CGFloat
    func body(content: Content) -> some View {
        content
            .overlay(
                HStack(spacing: 6) {
                    Circle().opacity(0.6 + 0.4 * sin(Double(phase) * .pi))
                    Circle().opacity(0.6 + 0.4 * sin(Double((phase + 0.33)) * .pi))
                    Circle().opacity(0.6 + 0.4 * sin(Double((phase + 0.66)) * .pi))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 44)
            )
    }
}
