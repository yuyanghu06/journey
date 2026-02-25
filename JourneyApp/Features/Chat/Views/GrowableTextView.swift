import SwiftUI

// MARK: - GrowableTextView
// A pill-shaped text input that expands vertically as the user types,
// capped at ~3 lines of visible content.

struct GrowableTextView: View {
    @Binding var text: String
    var placeholder: String = ""

    @State private var dynamicHeight: CGFloat = 38

    var body: some View {
        ZStack(alignment: .leading) {
            // Placeholder text, hidden once the user starts typing
            if text.isEmpty {
                Text(placeholder)
                    .font(DS.font(.body))
                    .foregroundColor(DS.Colors.tertiary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
            }

            TextEditor(text: $text)
                .font(DS.font(.body))
                .foregroundColor(DS.Colors.primary)
                .frame(minHeight: 38, maxHeight: min(max(dynamicHeight, 38), 120))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .onChange(of: text) { _ in recalcHeight() }
                .onAppear { recalcHeight() }
        }
        .background(DS.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous))
        .shadow(color: DS.Shadow.color, radius: 4, y: 1)
    }

    /// Recalculates the required height based on the current text content.
    private func recalcHeight() {
        let width = UIScreen.main.bounds.width - 140
        let size  = CGSize(width: width, height: .greatestFiniteMagnitude)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.preferredFont(forTextStyle: .body)]
        let rect  = (text as NSString).boundingRect(
            with: size,
            options: .usesLineFragmentOrigin,
            attributes: attrs,
            context: nil
        )
        dynamicHeight = rect.height + 22
    }
}
