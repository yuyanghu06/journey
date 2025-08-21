//
//  ContentView.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/20/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ChatView(viewModel: ChatViewModel())
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(viewModel: ChatViewModel())
    }
}

