//
//  openmeshApp.swift
//  openmesh-mac
//
//  Created by wesley on 2026/1/18.
//

import SwiftUI
import Foundation

@main
struct openmeshApp: App {
    @StateObject private var vpnManager = VPNManager()

    init() {
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
    }

    var body: some Scene {
        // 2. 使用 MenuBarExtra 代替 WindowGroup
        MenuBarExtra("OpenMesh", systemImage: "network") {
            // 3. 这里编写点击菜单后显示的菜单项
            VStack(spacing: 10) {
                Text("OpenMesh VPN")
                    .font(.headline)
                
                Toggle(isOn: Binding(
                    get: { vpnManager.isConnected },
                    set: { _ in vpnManager.toggleVPN() }
                )) {
                    Text(vpnManager.isConnected ? "断开连接" : "连接 VPN")
                }
                .toggleStyle(CheckboxToggleStyle())
                
                if vpnManager.isConnecting {
                    ProgressView("正在连接...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                }
                
                Divider() // 分割线
                
                Button("退出应用") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q") // 快捷键 Cmd+Q
            }
            .padding()
        }
    }
}

private enum RoutingRulesStore {
    static let appGroupID = "group.com.meshnetprotocol.OpenMesh"
    static let relativeDir = "OpenMesh"
    static let filename = "routing_rules.json"

    static func syncBundledRulesIntoAppGroupIfNeeded() {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        guard let bundledURL = Bundle.main.url(forResource: "routing_rules", withExtension: "json") else { return }

        let destDir = groupURL.appendingPathComponent(relativeDir, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        let destURL = destDir.appendingPathComponent(filename, isDirectory: false)

        guard let bundledVersion = readVersion(from: bundledURL) else { return }
        let existingVersion = readVersion(from: destURL)

        if existingVersion == nil {
            copy(bundledURL: bundledURL, to: destURL)
            return
        }

        if let existingVersion, bundledVersion > existingVersion {
            copy(bundledURL: bundledURL, to: destURL)
        }
    }

    private static func copy(bundledURL: URL, to destURL: URL) {
        do {
            let data = try Data(contentsOf: bundledURL)
            try data.write(to: destURL, options: [.atomic])
        } catch {
            // Ignore.
        }
    }

    private static func readVersion(from url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        guard let dict = obj as? [String: Any] else { return nil }
        if let v = dict["version"] as? Int { return v }
        if let v = dict["version"] as? NSNumber { return v.intValue }
        if let v = dict["version"] as? String { return Int(v) }
        return nil
    }
}
