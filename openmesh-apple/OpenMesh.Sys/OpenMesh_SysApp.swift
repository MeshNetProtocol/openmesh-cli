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
    @StateObject private var extensionManager = SystemExtensionInstaller()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    extensionManager.install()
                }
        }
    }
}

import SystemExtensions
import os

class SystemExtensionInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    @Published var status: String = "Idle"
    private let logger = Logger(subsystem: "com.meshnetprotocol.OpenMesh.macsys", category: "SystemExtensionInstaller")

    func install() {
        // Request activation for the specific System Extension Bundle ID
        // Note: This must match the Bundle Identifier in the System Extension target's Info.plist.
        
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: "com.meshnetprotocol.OpenMesh.macsys.vpn-extension", queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        status = "Requesting activation..."
        logger.info("Requesting activation for System Extension...")
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        status = "Replacing existing extension..."
        logger.info("Replacing existing extension...")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = "Requires user approval in System Settings."
        logger.warning("System Extension requires user approval in System Settings.")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        status = "Installation finished with result: \(result.rawValue)"
        logger.info("System Extension installation finished with result: \(result.rawValue)")
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        status = "Installation failed: \(error.localizedDescription)"
        logger.error("System Extension installation failed: \(error.localizedDescription)")
    }
}
