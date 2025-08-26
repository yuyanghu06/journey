//
//  MessageRow.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//

import Foundation
import SwiftUI

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
