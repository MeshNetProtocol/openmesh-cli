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
        MenuBarExtra {
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
        } label: {
            Label {
                Text("OpenMesh")
            } icon: {
                statusBarIcon
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }
            .labelStyle(.iconOnly)
        }
    }

    private var statusBarIcon: Image {
        Image(vpnManager.isConnected ? "mesh_on" : "mesh_off")
    }
}
