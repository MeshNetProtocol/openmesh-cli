//
//  OpenMeshApp.swift
//  OpenMesh
//
//  Created by wesley on 2026/1/8.
//

import SwiftUI

@main
struct OpenMeshApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    AppHUDOverlay(hud: AppHUD.shared)
                }
        }
    }
}
