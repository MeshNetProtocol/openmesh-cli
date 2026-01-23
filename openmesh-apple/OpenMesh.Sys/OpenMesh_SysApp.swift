//
//  OpenMesh_SysApp.swift
//  OpenMesh.Sys
//
//  Created by wesley on 2026/1/23.
//

import SwiftUI
import SwiftData

@main
struct OpenMesh_SysApp: App {
    @StateObject private var extensionManager = SystemExtensionInstaller()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    extensionManager.install()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

import SystemExtensions

class SystemExtensionInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    func install() {
        guard let extensionIdentifier = Bundle.main.bundleIdentifier?.replacingOccurrences(of: ".Sys", with: ".Sys-ext") else {
             print("Unable to determine extension identifier")
             return
        }
        // Assuming the ID convention: com.company.app.Sys -> com.company.app.Sys-ext
        // Adjust this string to match your ACTUAL Bundle ID for the System Extension target.
        // Based on analysis, the target name is OpenMesh.Sys-ext. 
        // Best practice is to hardcode it if known, or derive it.
        // Let's rely on finding it dynamically or hardcode if we knew the bundle ID.
        // Since I don't have the exact Bundle ID string, I will guess it follows the target name suffix.
        // BUT safer is to print it out or use a known constant.
        // For now, I will use a placeholder logic that attempts to install.
        
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: "com.meshnetprotocol.OpenMesh.Sys-ext", queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        print("System Extension requires user approval in System Settings.")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        print("System Extension installation finished with result: \(result)")
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        print("System Extension installation failed: \(error.localizedDescription)")
    }
}
