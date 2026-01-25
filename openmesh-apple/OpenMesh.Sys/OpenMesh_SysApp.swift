//
//  OpenMesh_SysApp.swift
//  OpenMesh.Sys
//
//  Created by wesley on 2026/1/23.
//

import SwiftUI
// import SwiftData - Removed as it requires macOS 14+
import Combine

@main
struct OpenMesh_SysApp: App {
    @StateObject private var extensionManager = SystemExtensionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(extensionManager)
                .onAppear {
                    // Only auto-install if not already set up, or let user click button.
                    // For now, consistent with previous behavior:
                    extensionManager.install()
                }
        }
    }
}
