//
//  OpenMesh_SysApp.swift
//  MeshFlux.Sys
//
//  Created by wesley on 2026/1/23.
//

import SwiftUI
import NetworkExtension
// import SwiftData - Removed as it requires macOS 14+
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var setupWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce Menu Bar App behavior (No Dock Icon)
        NSApp.setActivationPolicy(.accessory)
        
        // CRITICAL: Sync routing rules from bundle to App Group directory
        // This was missing in OpenMesh.Sys target, causing routing_rules.json to be unavailable
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
        
        // CRITICAL: Sync singbox base config if no user config exists yet
        // This ensures VPN can start with default config (user can customize later)
        syncBundledSingboxConfigIfNeeded()
        
        let manager = SystemExtensionManager.shared
        // If first launch or not installed, open the setup window immediately
        if manager.isFirstLaunch || manager.extensionState == .notInstalled {
            openSetupWindow()
        }
    }
    
    /// Sync bundled singbox_base_config.json to App Group if singbox_config.json doesn't exist
    private func syncBundledSingboxConfigIfNeeded() {
        let fileManager = FileManager.default
        
        // Get App Group container
        let appGroupID = "group.com.meshnetprotocol.OpenMesh.macsys"
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("WARNING: Cannot access App Group container: \(appGroupID)")
            return
        }
        
        let destDir = groupURL.appendingPathComponent("MeshFlux", isDirectory: true)
        let destURL = destDir.appendingPathComponent("singbox_config.json", isDirectory: false)
        
        // If user config already exists, don't overwrite
        if fileManager.fileExists(atPath: destURL.path) {
            print("singbox_config.json already exists, skipping sync")
            return
        }
        
        // Find bundled base config
        guard let bundledURL = Bundle.main.url(forResource: "singbox_base_config", withExtension: "json") else {
            print("WARNING: singbox_base_config.json not found in bundle")
            return
        }
        
        do {
            // Ensure directory exists
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
            
            // Copy bundled config as initial user config
            let data = try Data(contentsOf: bundledURL)
            try data.write(to: destURL, options: [.atomic])
            print("Successfully synced singbox_base_config.json to App Group as singbox_config.json")
        } catch {
            print("ERROR: Failed to sync singbox config: \(error.localizedDescription)")
        }
    }
    
    func openSetupWindow() {
        if setupWindow != nil {
            setupWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let manager = SystemExtensionManager.shared
        // Use OnboardingView in a hosting controller
        let onboardingView = OnboardingView(extensionManager: manager)
            .frame(minWidth: 500, minHeight: 650)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        
        window.center()
        window.title = "MeshFlux X Setup"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.isReleasedWhenClosed = false
        // Floating level ensures it's visible even without Dock activation
        window.level = .floating 
        
        self.setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct OpenMesh_SysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var extensionManager = SystemExtensionManager.shared

    var body: some Scene {
        MenuBarExtra {
            if extensionManager.extensionState != .ready {
                // Simplified menu when setup is needed
                Button("Open Setup Wizard") {
                    appDelegate.openSetupWindow()
                }
                Divider()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            } else {
                MainView(extensionManager: extensionManager)
                    .frame(width: 350, height: 500)
            }
        } label: {
            let imageName = extensionManager.vpnStatus == .connected ? "network.badge.shield.half.filled" : "network"
            Image(systemName: imageName)
        }
        .menuBarExtraStyle(.window)
    }
}
