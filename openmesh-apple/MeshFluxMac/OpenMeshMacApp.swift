//
//  openmeshApp.swift
//  meshflux-mac
//
//  Created by wesley on 2026/1/18.
//

import SwiftUI
import Foundation
import AppKit
import VPNLibrary
import OpenMeshGo

@main
struct openmeshApp: App {
    @StateObject private var vpnController = VPNController()

    init() {
        // LibboxSetup 使主 App 的 CommandClient 能连接 extension 的 command.sock（与 sing-box 一致）。
        configureLibbox()
    }

    private func configureLibbox() {
        let options = OMLibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.path
        options.workingPath = FilePath.workingDirectory.path
        options.tempPath = FilePath.cacheDirectory.path
        var err: NSError?
        OMLibboxSetup(options, &err)
        if let err {
            NSLog("MeshFluxMac OMLibboxSetup failed: %@", err.localizedDescription)
        }
    }

    var body: some Scene {
        // 主界面放在独立 Window 中，与 sing-box 一致；点击 sheet 时不会导致主窗口被系统收起。
        Window("MeshFlux", id: "main") {
            MenuContentView(vpnController: vpnController, onAppear: ensureDefaultProfileIfNeeded)
        }
        .defaultSize(width: 480, height: 560)
        .windowResizability(.contentSize)

        // 与 sing-box 一致：菜单栏为 .window，点击图标弹出小窗（状态 + 打开/退出）；主内容在独立 Window，sheet 不导致主窗消失。
        MenuBarExtra {
            MenuBarWindowContent(vpnController: vpnController)
        } label: {
            Label {
                Text("MeshFlux")
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
        Image(vpnController.isConnected ? "mesh_on" : "mesh_off")
    }

    /// 首次启动时若没有任何配置，自动从 bundle 安装自带默认配置（规则 + 服务器模板）。
    /// 若有配置但 selected_profile_id 无效（如偏好损坏被清空），自动选中第一个配置。
    private func ensureDefaultProfileIfNeeded() {
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

/// 与 sing-box MenuView 一致：菜单栏点击后弹出小窗口，含标题、状态、VPN 开关、ProfilePicker、「打开」「退出」。
private struct MenuBarWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var vpnController: VPNController

    @State private var isLoading = true
    @State private var profileList: [ProfilePreview] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var reasserting = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private static let menuWidth: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 + 状态（与 sing-box MenuHeader 一致）
            HStack {
                Text("MeshFlux")
                    .font(.headline)
                Spacer()
            }
            Toggle(isOn: Binding(
                get: { vpnController.isConnected },
                set: { _ in vpnController.toggleVPN() }
            )) {}
                .toggleStyle(.switch)
                .labelsHidden()
            if vpnController.isConnecting {
                Text("连接中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(vpnController.isConnected ? "已连接" : "未连接")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // ProfilePicker（与 sing-box MenuView.ProfilePicker 一致）
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
                .disabled(reasserting)
            }
            Divider()
            Button {
                openWindow(id: "main")
                // 激活应用并把主窗口置于最前，避免被其它 app 遮挡时「打开」看起来无反应
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    bringMainWindowToFront()
                }
            } label: {
                Label("打开", systemImage: "macwindow")
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
        .frame(minWidth: Self.menuWidth)
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            Task { await loadProfiles() }
        }
        .alert("错误", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "未知错误")
        }
    }

    private func loadProfiles() async {
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

/// 与 sing-box StartStopButton 一致：工具栏启停 VPN。
private struct StartStopButton: View {
    @ObservedObject var vpnController: VPNController
    @State private var profileList: [Profile] = []
    @State private var selectedID: Int64 = -1

    var body: some View {
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
                if vpnController.isConnected {
                    NavigationPage.groups.label.tag(NavigationPage.groups)
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
        .frame(width: 480, height: 560)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StartStopButton(vpnController: vpnController)
            }
        }
        .environment(\.meshSelection, $selection)
        .onAppear {
            onAppear?()
            if selection == nil { selection = .dashboard }
        }
        .onChange(of: vpnController.isConnected) { _ in
            if let s = selection, !s.visible(vpnConnected: vpnController.isConnected) {
                selection = .dashboard
            }
        }
    }
}

/// 将主窗口置于最前；点击菜单栏「打开」时若主窗已被遮挡，调用此方法可将其带到前台。
private func bringMainWindowToFront() {
    let app = NSApplication.shared
    app.activate(ignoringOtherApps: true)
    // SwiftUI Window("MeshFlux", id: "main") 的窗口标题为 "MeshFlux"，或 identifier 含 "main"
    guard let main = app.windows.first(where: { win in
        win.title == "MeshFlux" || (win.identifier?.rawValue ?? "").contains("main")
    }) else { return }
    main.makeKeyAndOrderFront(nil)
}
