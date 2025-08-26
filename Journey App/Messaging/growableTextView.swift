//
//  GrowableTextView.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//
import SwiftUI

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
