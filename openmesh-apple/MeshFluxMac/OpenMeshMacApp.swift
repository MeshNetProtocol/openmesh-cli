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

/// 与 sing-box 一致：VPN/ExtensionProfile 的 load 全部延后到此通知之后，避免 init 阶段访问 CFPrefs 触发沙盒错误。
extension Notification.Name {
    static let appLaunchDidFinish = Notification.Name("com.meshnetprotocol.OpenMesh.appLaunchDidFinish")
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

/// 仅在用户点击菜单「设置」时创建并显示设置窗口，启动时不创建任何设置窗口。
private final class SettingsWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    weak var vpnController: VPNController?
    var showMenuBarExtraBinding: Binding<Bool>?
    var onAppear: (() -> Void)?
    private weak var window: NSWindow?

    func configure(vpnController: VPNController, showMenuBarExtra: Binding<Bool>, onAppear: @escaping () -> Void) {
        self.vpnController = vpnController
        self.showMenuBarExtraBinding = showMenuBarExtra
        self.onAppear = onAppear
    }

    func show() {
        guard let vpn = vpnController, let binding = showMenuBarExtraBinding, let onAppear = onAppear else { return }
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.level = .floating
            w.makeKeyAndOrderFront(nil)
            return
        }
        let contentView = MenuContentView(vpnController: vpn, onAppear: onAppear)
            .environment(\.showMenuBarExtra, binding)
        let hosting = NSHostingView(rootView: contentView)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hosting
        w.title = "MeshFlux"
        w.minSize = NSSize(width: 760, height: 600)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

/// 菜单栏图标是否显示；本应用以菜单栏为主入口，始终为 true，仅注入环境供 App 设置页占位 UI 使用。
private struct ShowMenuBarExtraKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}
extension EnvironmentValues {
    var showMenuBarExtra: Binding<Bool> {
        get { self[ShowMenuBarExtraKey.self] }
        set { self[ShowMenuBarExtraKey.self] = newValue }
    }
}

@main
struct openmeshApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var holder = VPNControllerHolder()
    @StateObject private var settingsPresenter = SettingsWindowPresenter()
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
                    settingsPresenter: settingsPresenter,
                    showMenuBarExtra: $showMenuBarExtra,
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

/// 与 sing-box EnvironmentValues.selection 一致：侧栏选中页。
private struct SelectionKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPage?> = .constant(.dashboard)
}
extension EnvironmentValues {
    var meshSelection: Binding<NavigationPage?> {
        get { self[SelectionKey.self] }
        set { self[SelectionKey.self] = newValue }
    }
}

/// 菜单栏弹窗顶部 Tab：VPN / MeshWallet / 设置
private enum MenuBarTab: String, CaseIterable {
    case vpn = "VPN"
    case meshWallet = "MeshWallet"
    case settings = "设置"
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

/// 菜单栏辅助弹窗：宽版带 Tab 切换；VPN Tab 为原菜单内容，其余 Tab 暂空。
private struct MenuBarWindowContent: View {
    @ObservedObject var vpnController: VPNController
    @ObservedObject var settingsPresenter: SettingsWindowPresenter
    var showMenuBarExtra: Binding<Bool>
    var onAppear: () -> Void

    @State private var selectedTab: MenuBarTab = .vpn
    @State private var isLoading = true
    @State private var profileList: [ProfilePreview] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var reasserting = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private static let menuWidth: CGFloat = 400

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
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(MenuBarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            switch selectedTab {
            case .vpn:
                vpnTabContent
            case .meshWallet:
                meshWalletTabContent
            case .settings:
                settingsTabContent
            }
        }
        .frame(minWidth: Self.menuWidth)
        .onAppear {
            cfPrefsTrace("MenuBarWindowContent onAppear (menu shown)")
            onAppear()  // 首次打开菜单时即确保默认配置（不依赖用户先点「设置」）
            settingsPresenter.configure(vpnController: vpnController, showMenuBarExtra: showMenuBarExtra, onAppear: onAppear)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            Task { await loadProfiles() }
        }
        .alert("错误", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "未知错误")
        }
    }

    @ViewBuilder
    private var vpnTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MeshFlux")
                    .font(.headline)
                Spacer()
            }
            Text(Self.displayVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(isOn: Binding(
                get: { vpnController.isConnected },
                set: { _ in vpnController.toggleVPN() }
            )) {}
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(vpnController.isConnecting)
            if vpnController.isConnecting {
                Text("连接中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(vpnController.isConnected ? "已连接" : "未连接")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .onAppear { Task { await loadProfiles() } }
            } else if profileList.isEmpty {
                Text("暂无配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { selectedProfileID },
                    set: { newId in
                        selectedProfileID = newId
                        reasserting = true
                        Task { await switchProfile(newId) }
                    }
                )) {
                    ForEach(profileList) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(reasserting || vpnController.isConnecting)
            }
            Divider()
            Button {
                settingsPresenter.show()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var meshWalletTabContent: some View {
        VStack {
            Spacer()
            Text("敬请期待")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        VStack {
            Spacer()
            Text("敬请期待")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// 与 sing-box StartStopButton 一致：工具栏启停 VPN。连接中时禁用并在旁显示提示，防止重复点击。
private struct StartStopButton: View {
    @ObservedObject var vpnController: VPNController
    @State private var profileList: [Profile] = []
    @State private var selectedID: Int64 = -1

    var body: some View {
        HStack(spacing: 8) {
            Button {
                vpnController.toggleVPN()
            } label: {
                if vpnController.isConnected {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Start", systemImage: "play.fill")
                }
            }
            .disabled(vpnController.isConnecting || selectedID < 0)

            if vpnController.isConnecting {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("VPN 正在启动中，请勿重复点击")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        let list = (try? await ProfileManager.list()) ?? []
        let id = await SharedPreferences.selectedProfileID.get()
        await MainActor.run {
            profileList = list
            selectedID = list.isEmpty ? -1 : (list.first(where: { $0.mustID == id })?.mustID ?? list[0].mustID)
        }
    }
}

/// 与 sing-box SidebarView 一致：按 NavigationPage 与 visible(vpnConnected) 展示侧栏。
private struct SidebarView: View {
    @Environment(\.meshSelection) private var selection
    @ObservedObject var vpnController: VPNController

    var body: some View {
        List(selection: selection) {
            Section(NavigationPage.dashboardSectionTitle) {
                NavigationPage.dashboard.label.tag(NavigationPage.dashboard)
                // 与 sing-box SidebarView 一致：Groups、Connections 仅 VPN 已连接时显示
                if vpnController.isConnected {
                    NavigationPage.groups.label.tag(NavigationPage.groups)
                    NavigationPage.connections.label.tag(NavigationPage.connections)
                }
            }
            Divider()
            ForEach(NavigationPage.defaultPages.filter { $0.visible(vpnConnected: vpnController.isConnected) }) { page in
                page.label.tag(page)
            }
            Section {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .frame(minWidth: 150)
        .onChange(of: vpnController.isConnected) { _ in
            if let s = selection.wrappedValue, !s.visible(vpnConnected: vpnController.isConnected) {
                selection.wrappedValue = .dashboard
            }
        }
    }
}

private struct MenuContentView: View {
    @ObservedObject var vpnController: VPNController
    var onAppear: (() -> Void)?
    @State private var selection: NavigationPage? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(vpnController: vpnController)
        } detail: {
            NavigationStack {
                (selection ?? .dashboard).contentView(vpnController: vpnController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle((selection ?? .dashboard).title)
            }
        }
        .frame(minWidth: 760, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StartStopButton(vpnController: vpnController)
            }
        }
        .environment(\.meshSelection, $selection)
        .onAppear {
            onAppear?()
            if selection == nil { selection = .dashboard }
            DispatchQueue.main.async { setSettingsWindowFloating() }
        }
        .onChange(of: vpnController.isConnected) { _ in
            if let s = selection, !s.visible(vpnConnected: vpnController.isConnected) {
                selection = .dashboard
            }
        }
    }
}

/// 将设置窗口设为「置顶」，使其浮在所有其他软件窗口之上，便于用户操作且关闭后如需再开只需点菜单「设置」。
private func setSettingsWindowFloating() {
    guard let main = NSApplication.shared.windows.first(where: { win in
        win.title == "MeshFlux" || (win.identifier?.rawValue ?? "").contains("main")
    }) else { return }
    main.level = .floating
}

/// 将辅助设置窗口置于最前并设为「置顶」；点击菜单栏「设置」时调用。
private func bringMainWindowToFront() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    guard let main = NSApplication.shared.windows.first(where: { win in
        win.title == "MeshFlux" || (win.identifier?.rawValue ?? "").contains("main")
    }) else { return }
    main.level = .floating
    main.makeKeyAndOrderFront(nil)
}
