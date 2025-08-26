//
//  Journey_AppApp.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/20/25.
//

import SwiftUI

@main
struct Journey_AppApp: App {
    @StateObject private var auth = AuthService()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
        }
    }
}
