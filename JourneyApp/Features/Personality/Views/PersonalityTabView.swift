import SwiftUI

// MARK: - PersonalityTabView
// Root view for the "Past Self" tab.
// Provides a custom segmented picker: Chat | History | Context.

struct PersonalityTabView: View {

    enum Section: String, CaseIterable {
        case chat    = "Chat"
        case history = "History"
        case context = "Context"
    }

    @State private var selectedSection: Section = .chat

    var body: some View {
        NavigationStack {
            ZStack {
                // Warm lavender tint background to signal this is a different mode
                DS.Colors.background
                    .overlay(DS.Colors.softLavender.opacity(0.07))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    sectionPicker
                    Divider().opacity(0.08)

                    ZStack {
                        PersonalitySessionView()
                            .opacity(selectedSection == .chat    ? 1 : 0)
                            .allowsHitTesting(selectedSection == .chat)
                        PersonalityHistoryView()
                            .opacity(selectedSection == .history ? 1 : 0)
                            .allowsHitTesting(selectedSection == .history)
                        UploadContextView()
                            .opacity(selectedSection == .context ? 1 : 0)
                            .allowsHitTesting(selectedSection == .context)
                    }
                    .animation(DS.Anim.subtle, value: selectedSection)
                }
            }
            .navigationTitle("Past Self")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Segmented Picker

    private var sectionPicker: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(Section.allCases, id: \.self) { section in
                Button {
                    withAnimation(DS.Anim.gentle) { selectedSection = section }
                } label: {
                    Text(section.rawValue)
                        .font(DS.font(.subheadline, weight: selectedSection == section ? .semibold : .regular))
                        .foregroundColor(selectedSection == section ? DS.Colors.softLavender : DS.Colors.tertiary)
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedSection == section
                                ? DS.Colors.softLavender.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Colors.surface)
    }
}
