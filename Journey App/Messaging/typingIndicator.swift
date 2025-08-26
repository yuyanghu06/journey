//
//  typingIndicator.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//

import SwiftUI

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
