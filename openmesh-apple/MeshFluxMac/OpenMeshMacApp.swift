//
//  openmeshApp.swift
//  meshflux-mac
//
//  Created by wesley on 2026/1/18.
//

import SwiftUI
import Foundation
import AppKit
import Combine
import VPNLibrary
import OpenMeshGo
#if os(macOS)
import ServiceManagement
#endif

/// 与 sing-box 一致：VPN/ExtensionProfile 的 load 全部延后到此通知之后，避免 init 阶段访问 CFPrefs 触发沙盒错误。
extension Notification.Name {
    static let appLaunchDidFinish = Notification.Name("com.meshnetprotocol.OpenMesh.appLaunchDidFinish")
    static let providerConfigDidUpdate = Notification.Name("com.meshnetprotocol.OpenMesh.providerConfigDidUpdate")
}

// 设计：以菜单栏为主入口，弹窗与主窗口均为辅助界面；关闭主窗口或弹窗仅关窗，不退出进程；仅通过「退出」按钮结束进程。
/// 关闭主窗口时不退出应用，保证辅助窗口关闭后进程继续在菜单栏运行。
/// 设为 .accessory：不显示在 Dock，仅菜单栏图标；弹窗时也不在 Dock 出现图标。

/// Libbox 路径配置；与 sing-box clients/apple 一致，在 applicationDidFinishLaunching 中调用，
/// 避免在 App init 中访问 FilePath 触发 CFPrefs (Container: null) 沙盒错误。
/// 路径使用 relativePath，与 upstream MacLibrary/ApplicationDelegate、ExtensionProvider 一致。
private func configureLibbox() {
    cfPrefsTrace("configureLibbox start (FilePath access)")
    let options = OMLibboxSetupOptions()
    options.basePath = FilePath.sharedDirectory.relativePath
    options.workingPath = FilePath.workingDirectory.relativePath
    options.tempPath = FilePath.cacheDirectory.relativePath
    var err: NSError?
    OMLibboxSetup(options, &err)
    if let err {
        NSLog("MeshFluxMac OMLibboxSetup failed: %@", err.localizedDescription)
    }
}

private class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        cfPrefsTrace("applicationDidFinishLaunching start")
        NSApp.setActivationPolicy(.accessory)
        // 与 sing-box 一致：在 applicationDidFinishLaunching 内做 Libbox 路径配置，沙盒容器已就绪。
        configureLibbox()
        cfPrefsTrace("configureLibbox end")
        do {
            let dirs = try AppPaths.ensureDirs()
            NSLog("MeshFluxMac AppPaths: appSupport=%@ caches=%@", dirs.appSupport.path, dirs.caches.path)
        } catch {
            NSLog("MeshFluxMac AppPaths.ensureDirs failed: %@", String(describing: error))
        }
        // Ensure routing_rules.json exists in App Group so the VPN extension can inject it deterministically.
        // If missing, the extension falls back to a minimal built-in rule set (Google only).
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
        // 先创建 VPNController（会创建 VPNManager 并注册 appLaunchDidFinish 观察者），再 post 通知
        cfPrefsTrace("createIfNeeded (before post)")
        AppState.holder?.createIfNeeded()
        cfPrefsTrace("post appLaunchDidFinish")
        NotificationCenter.default.post(name: .appLaunchDidFinish, object: nil)
        cfPrefsTrace("applicationDidFinishLaunching end")
        // 启动后在一段时间内多次放弃焦点：系统/SwiftUI 可能在启动完成一段时间后才激活本应用，单次 deactivate 不够
        for delay in [0.0, 0.15, 0.35, 0.6, 1.0, 1.5] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !Self.hasSettingsWindowKey else { return }
                NSApp.deactivate()
            }
        }
    }

    /// 用户是否已打开我们的设置窗口（为 key 窗口），若是则不再自动 deactivate
    private static var hasSettingsWindowKey: Bool {
        guard let key = NSApp.keyWindow else { return false }
        return key.title == "MeshFlux" || (key.identifier?.rawValue ?? "").contains("main")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

/// 延迟创建 VPNController，仅在 applicationDidFinishLaunching 之后创建，避免 0–1 之间触发 CFPrefs。
private final class VPNControllerHolder: ObservableObject {
    private(set) var controller: VPNController?
    func createIfNeeded() {
        guard controller == nil else { return }
        controller = VPNController()
        objectWillChange.send()
    }
}

/// 用于在 applicationDidFinishLaunching 中触发 holder.createIfNeeded()；body 首次求值时会设置。
private enum AppState {
    static weak var holder: VPNControllerHolder?
}


@main
struct openmeshApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var holder = VPNControllerHolder()
    @State private var showMenuBarExtra = true

    init() {
        cfPrefsTrace("openmeshApp init")
    }

    var body: some Scene {
        let _ = cfPrefsTrace("openmeshApp body (Scene built)")
        let _ = AppState.holder = holder
        // 启动时不创建设置窗口，仅保留菜单栏；VPNController 延后到 applicationDidFinishLaunching 后创建，避免 0–1 间 CFPrefs。
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            if let vpnController = holder.controller {
                MenuBarWindowContent(
                    vpnController: vpnController,
                    onAppear: ensureDefaultProfileIfNeeded
                )
            } else {
                MenuBarPlaceholderView()
            }
        } label: {
            Label {
                Text("MeshFlux")
            } icon: {
                MenuBarIconView(holder: holder)
            }
            .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }

    /// 首次启动时若没有任何配置，自动从 bundle 安装自带默认配置（规则 + 服务器模板）。
    /// 若有配置但 selected_profile_id 无效（如偏好损坏被清空），自动选中第一个配置。
    private func ensureDefaultProfileIfNeeded() {
        cfPrefsTrace("ensureDefaultProfileIfNeeded (menu onAppear callback)")
        Task {
            do {
                let installed = try await DefaultProfileHelper.installDefaultProfileFromBundle()
                if installed != nil {
                    await MainActor.run {
                        NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                    }
                    return
                }
                // List was not empty; ensure we have a valid selection (repair after corrupted preference clear).
                let list = try? await ProfileManager.list()
                let id = await SharedPreferences.selectedProfileID.get()
                if id < 0, let list = list, !list.isEmpty {
                    await SharedPreferences.selectedProfileID.set(list[0].mustID)
                    await MainActor.run {
                        NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                    }
                }
            } catch {
                // Ignore; user can click "使用默认配置" in Profiles view
            }
        }
    }
}

/// 菜单栏弹窗顶部 Tab：设置 / 流量市场 / home
private enum MenuBarTab: String, CaseIterable {
    case settings = "Dashboard"
    case trafficMarket = "Market"
    case home = "Settings"
}

/// 菜单栏图标：当有 VPNController 时观察其 isConnected，以便连接状态变化时刷新图标。
private struct MenuBarIconView: View {
    @ObservedObject var holder: VPNControllerHolder
    var body: some View {
        Group {
            if let controller = holder.controller {
                MenuBarIconObserving(controller: controller)
            } else {
                Image("mesh_off")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }
        }
    }
}

private struct MenuBarIconObserving: View {
    @ObservedObject var controller: VPNController
    var body: some View {
        Image(controller.isConnected ? "mesh_on" : "mesh_off")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
    }
}

/// 在 VPNController 创建前显示的占位内容（避免 0–1 间创建 StateObject 触发 CFPrefs）。
private struct MenuBarPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView().scaleEffect(0.9)
            Text("启动中…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(minWidth: 200, minHeight: 80)
        .padding()
    }
}

/// 菜单栏辅助弹窗：宽版带 Tab 切换；第 1 Tab 为主控制台（UI-only 迭代中）。
private struct MenuBarWindowContent: View {
    @ObservedObject var vpnController: VPNController
    var onAppear: () -> Void

    @State private var selectedTab: MenuBarTab = .settings
    @State private var openAnchorX: CGFloat?
    @State private var isLoading = true
    @State private var profileList: [ProfilePreview] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var reasserting = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private static let menuWidth: CGFloat = 420
    private static let menuMinHeight: CGFloat = 520

    /// 菜单栏显示的版本：OMLibboxVersion() 有效则用，否则用 App 的 CFBundleShortVersionString
    private static var displayVersion: String {
        let libbox = OMLibboxVersion()
        if !libbox.isEmpty, libbox.lowercased() != "unknown" {
            return libbox
        }
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if !short.isEmpty { return build.isEmpty ? short : "\(short) (\(build))" }
        return libbox.isEmpty ? "—" : libbox
    }

    var body: some View {
        let _ = cfPrefsTrace("MenuBarWindowContent body (menu popup content)")
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 0) {
                MenuTopTabBar(selected: $selectedTab)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                switch selectedTab {
                case .settings:
                    settingsPrimaryTabContent
                case .trafficMarket:
                    trafficMarketTabContent
                case .home:
                    homeTabContent
                }
            }
        }
        .frame(minWidth: Self.menuWidth, minHeight: Self.menuMinHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            cfPrefsTrace("MenuBarWindowContent onAppear (menu shown)")
            onAppear()  // 首次打开菜单时即确保默认配置（不依赖用户先点「设置」）
            if openAnchorX == nil {
                openAnchorX = NSEvent.mouseLocation.x
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                centerVisibleMenuBarExtraWindow(anchorX: openAnchorX, approxWidth: Self.menuWidth)
            }
        }
        .onChange(of: selectedTab) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                centerVisibleMenuBarExtraWindow(anchorX: openAnchorX, approxWidth: Self.menuWidth)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            Task { await loadProfiles() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerConfigDidUpdate)) { note in
            guard vpnController.isConnected else { return }
            let updatedProfileID = note.userInfo?["profile_id"] as? Int64
            guard updatedProfileID == nil || updatedProfileID == selectedProfileID else { return }
            Task { await vpnController.reconnectToApplySettings() }
        }
        .alert("错误", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "未知错误")
        }
    }

    @ViewBuilder
    private var settingsPrimaryTabContent: some View {
        MenuSettingsPrimaryTabView(
            vpnController: vpnController,
            displayVersion: Self.displayVersion,
            isLoadingProfiles: isLoading,
            profileList: profileList,
            selectedProfileID: $selectedProfileID,
            isReasserting: $reasserting,
            onLoadProfiles: { await loadProfiles() },
            onSwitchProfile: { id in await switchProfile(id) }
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var trafficMarketTabContent: some View {
        TrafficMarketView(vpnController: vpnController)
    }

    @ViewBuilder
    private var homeTabContent: some View {
        MenuGeneralSettingsTab(vpnController: vpnController)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadProfiles() async {
        cfPrefsTrace("MenuBarWindowContent loadProfiles() start (ProfileManager.list + SharedPreferences)")
        defer { isLoading = false }
        do {
            let list = try await ProfileManager.list()
            profileList = list.map { ProfilePreview($0) }
            var sid = await SharedPreferences.selectedProfileID.get()
            if profileList.isEmpty {
                selectedProfileID = -1
                return
            }
            if profileList.first(where: { $0.id == sid }) == nil {
                sid = profileList[0].id
                await SharedPreferences.selectedProfileID.set(sid)
            }
            await MainActor.run { selectedProfileID = sid }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func switchProfile(_ newId: Int64) async {
        await SharedPreferences.selectedProfileID.set(newId)
        NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
        if vpnController.isConnected {
            vpnController.requestExtensionReload()
        }
        await MainActor.run { reasserting = false }
    }
}

private struct MenuGeneralSettingsTab: View {
    @ObservedObject var vpnController: VPNController
    @State private var startAtLogin = false
    @State private var unmatchedTrafficOutbound = "direct"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Start at login")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Spacer(minLength: 8)
                    Toggle("", isOn: $startAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: startAtLogin) { enabled in
                            setStartAtLogin(enabled)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("未命中流量出口")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $unmatchedTrafficOutbound) {
                            Text("Proxy").tag("proxy")
                            Text("Direct").tag("direct")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .onChange(of: unmatchedTrafficOutbound) { value in
                            Task { await vpnController.setUnmatchedTrafficOutbound(value) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 2)
        .task {
            #if os(macOS)
            startAtLogin = (SMAppService.mainApp.status == .enabled)
            #endif
            let outbound = await SharedPreferences.unmatchedTrafficOutbound.get()
            unmatchedTrafficOutbound = outbound == "proxy" ? "proxy" : "direct"
        }
    }

    private func setStartAtLogin(_ enabled: Bool) {
        #if os(macOS)
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
                startAtLogin = true
            } else {
                try SMAppService.mainApp.unregister()
                startAtLogin = false
            }
        } catch {
            startAtLogin = (SMAppService.mainApp.status == .enabled)
            NSLog("MeshFluxMac StartAtLogin toggle failed: %@", error.localizedDescription)
        }
        #endif
    }
}

private struct MenuTopTabBar: View {
    @Binding var selected: MenuBarTab

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 18) {
                tabButton(.settings)
                tabButton(.trafficMarket)
                tabButton(.home)
                Spacer(minLength: 0)
            }
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: MenuBarTab) -> some View {
        Button {
            selected = tab
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: selected == tab ? .semibold : .regular))
                    .foregroundColor(selected == tab ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                Rectangle()
                    .fill(selected == tab ? Color.orange : Color.clear)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

/// 通过鼠标位置估算状态栏图标中心点，并将菜单栏弹窗在 X 方向居中对齐。
/// 说明：SwiftUI 的 MenuBarExtra 未公开提供 anchor/placement 控制，本方法为“轻量对齐修正”。
private func centerVisibleMenuBarExtraWindow(anchorX: CGFloat?, approxWidth: CGFloat) {
    let anchor = anchorX ?? NSEvent.mouseLocation.x
    let candidates = NSApp.windows.filter { w in
        w.isVisible &&
            w.title.isEmpty &&
            abs(w.frame.width - approxWidth) < 80 &&
            w.level.rawValue >= NSWindow.Level.statusBar.rawValue
    }
    guard let w = candidates.first else { return }

    let screenFrame = w.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let desiredX = anchor - (w.frame.width / 2.0)
    var frame = w.frame
    frame.origin.x = min(max(desiredX, screenFrame.minX), screenFrame.maxX - frame.width)
    w.setFrame(frame, display: false, animate: false)
}
