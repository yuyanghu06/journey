import SwiftUI
import Foundation

// MARK: - Views

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @FocusState private var focused: Bool
    @State private var goToCalendar = false
    @State private var isLoadingCalendar = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var auth: AuthService
    
    init(auth: AuthService) {
            _viewModel = StateObject(wrappedValue: ChatViewModel(auth: auth))
        }
    
    public func summarizeAndPostOnBackground() {
        // Ensure we have messages to summarize
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "SummarizeAndPost") {
            // Expiration handler: end the task if time runs out
            UIApplication.shared.endBackgroundTask(taskId)
        }
        guard viewModel.messages.count != 1 else {
            UIApplication.shared.endBackgroundTask(taskId)
            return
        }
        let messagesSnapshot = viewModel.messages
        // Call your existing summarizer (completion-based)
        summarizeGPT(messagesSnapshot) { summary in
            let compressed = compressMessages(messagesSnapshot) ?? " "
            let dateString = isoDateString()
            Task{
                try? await self.auth.postCompressedHistory(
                    date: dateString,
                    compressedHistory: compressed,
                    summary: summary ?? ""
                )
            }
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    var body: some View {
        Group {
            if viewModel.messageLoading {
                LoadingView()
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        header
                        Divider().opacity(0.2)
                        messageList
                        inputBar
                    }
                    .background(
                        NavigationLink(destination: isLoadingCalendar ? AnyView(LoadingView()) : AnyView(CalendarView()), isActive: $goToCalendar) {
                            EmptyView()
                        }
                        .hidden()
                    )
                    .background(Color(.systemGroupedBackground))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SummarizeAndPostOnBackground"))) { _ in
            summarizeAndPostOnBackground()
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
            
            NavigationLink(destination: BugView().environmentObject(auth)) {
                Image(systemName: "ladybug")
                    .font(.title2)
                    .padding(8)
            }
            
            //MARK: Calendar Loading Logic
            Button {
                isLoadingCalendar = true
                goToCalendar = true
                if viewModel.messages.count == 1 {
                    self.viewModel.summary = "No summary available."
                    isLoadingCalendar = false
                    return
                }
                summarizeGPT(viewModel.messages) { entry in
                    self.viewModel.summary = entry ?? "No summary available."
                    if let compressed = compressMessages(self.viewModel.messages) {
                        let today = isoDateString()
                        Task {
                            try? await auth.postCompressedHistory(
                                date: today,
                                compressedHistory: compressed,
                                summary: self.viewModel.summary
                            )
                        }
                    } else {
                        print("Could not compress messages; skipping POST")
                    }
                    isLoadingCalendar = false
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
