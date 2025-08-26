//
//  loadingView.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            Text("Loading...")
                .foregroundColor(.gray)
                .font(.title)
        }
    }
}
