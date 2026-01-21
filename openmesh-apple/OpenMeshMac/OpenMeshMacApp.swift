//
//  openmeshApp.swift
//  openmesh-mac
//
//  Created by wesley on 2026/1/18.
//

import SwiftUI
import Foundation
import AppKit

@main
struct openmeshApp: App {
    @StateObject private var vpnManager = VPNManager()

    init() {
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
    }

    var body: some Scene {
        // 2. 使用 MenuBarExtra 代替 WindowGroup
        MenuBarExtra {
            MenuContentView(vpnManager: vpnManager)
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
        .menuBarExtraStyle(.window)
    }

    private var statusBarIcon: Image {
        Image(vpnManager.isConnected ? "mesh_on" : "mesh_off")
    }
}

private struct MenuContentView: View {
    @ObservedObject var vpnManager: VPNManager
    @State private var isGlobalMode: Bool = (RoutingModeStore.read() == .global)

    var body: some View {
        TabView {
            vpnTab
                .tabItem { Text("VPN") }
            systemTab
                .tabItem { Text("System") }
        }
        .frame(width: 360, height: 520)
    }

    private var vpnTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenMesh VPN")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { isGlobalMode },
                set: { newValue in
                    isGlobalMode = newValue
                    RoutingModeStore.write(newValue ? .global : .rule)
                }
            )) {
                Text(isGlobalMode ? "路由：全局" : "路由：规则")
            }
            .toggleStyle(.switch)

            Toggle(isOn: Binding(
                get: { vpnManager.isConnected },
                set: { _ in vpnManager.toggleVPN() }
            )) {
                Text(vpnManager.isConnected ? "断开连接" : "连接 VPN")
            }
            .toggleStyle(.switch)

            if vpnManager.isConnecting {
                ProgressView("正在连接...")
                    .progressViewStyle(.circular)
            }

            Text(isGlobalMode ? "全局模式：所有流量走代理" : "规则模式：命中规则走代理，未命中走直连")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("退出应用") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
    }

    private var systemTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System")
                .font(.headline)
            Text("TODO")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}
