//
//  OpenMesh_SysApp.swift
//  OpenMesh.Sys
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
        
        let manager = SystemExtensionManager.shared
        // If first launch or not installed, open the setup window immediately
        if manager.isFirstLaunch || manager.extensionState == .notInstalled {
            openSetupWindow()
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
        window.title = "OpenMesh X Setup"
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
