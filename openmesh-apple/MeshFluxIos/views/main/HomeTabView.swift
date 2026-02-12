import Foundation
import SwiftUI
import NetworkExtension
import UIKit
import VPNLibrary
import OpenMeshGo

private func vpnStatusText(_ s: NEVPNStatus) -> String {
    switch s {
    case .connected: return "已连接"
    case .connecting, .reasserting: return "连接中…"
    default: return "未连接"
    }
}

private func prettyVersionString() -> String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    if !short.isEmpty { return build.isEmpty ? short : "\(short) (\(build))" }
    return "—"
}

private func formatTrafficBytes(_ value: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    formatter.isAdaptive = true
    formatter.includesUnit = true
    formatter.includesCount = true
    return formatter.string(fromByteCount: max(0, value))
}

struct HomeTabView: View {
    @EnvironmentObject private var vpnController: VPNController
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var statusClient = StatusCommandClient()
    @StateObject private var groupClient = GroupCommandClient()

    @State private var profileList: [Profile] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var profileLoadError: String?

    @State private var showOutboundPicker = false
    @State private var urlTesting = false
    @State private var vpnActionBusy = false
    @State private var canActivateCommandClients = false
    @State private var sceneTask: Task<Void, Never>?
    @State private var startupLoadTask: Task<Void, Never>?
    @State private var startupProfilesTask: Task<Void, Never>?
    @State private var startupActivateClientsTask: Task<Void, Never>?
    @State private var showProviderRequiredAlert = false

    private let onOpenMarket: (() -> Void)?

    init(onOpenMarket: (() -> Void)? = nil) {
        self.onOpenMarket = onOpenMarket
    }

    private var vpnStatus: String { vpnStatusText(vpnController.status) }
    private var isConnecting: Bool { vpnController.isConnecting }
    private var appVersion: String { prettyVersionString() }
    private var isVPNTransitioning: Bool {
        vpnActionBusy || vpnController.status == .disconnecting || vpnController.status == .connecting || vpnController.status == .reasserting
    }

    private var currentGroup: OutboundGroupModel? {
        // Prefer selector group for UI.
        if let proxy = groupClient.groups.first(where: { $0.tag.lowercased() == "proxy" && $0.selectable }) {
            return proxy
        }
        if let selector = groupClient.groups.first(where: { $0.type.lowercased() == "selector" && $0.selectable }) {
            return selector
        }
        return groupClient.groups.first
    }

    private var currentOutboundDisplay: String {
        guard let g = currentGroup else { return "—" }
        if g.selected.isEmpty { return g.tag }
        return g.selected
    }

    private var currentOutboundDelayText: String? {
        guard let g = currentGroup else { return nil }
        if let match = g.items.first(where: { $0.tag == g.selected || (g.selected.isEmpty && $0.tag == g.tag) }) {
            if match.urlTestDelay > 0 { return match.delayString }
        }
        if let selected = g.items.first(where: { $0.tag == g.selected }), selected.urlTestDelay > 0 {
            return selected.delayString
        }
        return nil
    }

    private var totalUplinkText: String {
        guard let msg = statusClient.status, msg.trafficAvailable else { return "—" }
        return formatTrafficBytes(Int64(msg.uplinkTotal))
    }

    private var totalDownlinkText: String {
        guard let msg = statusClient.status, msg.trafficAvailable else { return "—" }
        return formatTrafficBytes(Int64(msg.downlinkTotal))
    }

    private var selectedProfileName: String {
        guard let selected = profileList.first(where: { $0.mustID == selectedProfileID }) else { return "未安装供应商（请前往 Market）" }
        return selected.name
    }

    private var hasUsableProvider: Bool {
        selectedProfileID > 0 && profileList.contains(where: { $0.mustID == selectedProfileID })
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.74, green: 0.84, blue: 0.94),
                    Color(red: 0.67, green: 0.79, blue: 0.91),
                    Color(red: 0.58, green: 0.70, blue: 0.82),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    merchantCard
                    trafficCard
                    outboundCard
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .disabled(isVPNTransitioning)
            .overlay {
                if isVPNTransitioning {
                    ZStack {
                        Color.black.opacity(0.20)
                            .ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(1.05)
                            Text(vpnController.status == .disconnecting ? "正在断开 VPN…" : "正在连接 VPN…")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.68))
                        )
                    }
                    .transition(.opacity)
                }
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showOutboundPicker) {
            NavigationView {
                OutboundPickerSheet(
                    groupClient: groupClient,
                    groupTag: currentGroup?.tag
                )
            }
        }
        .onAppear {
            startupLoadTask?.cancel()
            startupProfilesTask?.cancel()
            startupActivateClientsTask?.cancel()
            startupLoadTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
                    try Task.checkCancellation()
                } catch {
                    return
                }
                await vpnController.load()
            }
            startupProfilesTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
                    try Task.checkCancellation()
                } catch {
                    return
                }
                await loadProfiles()
            }
            startupActivateClientsTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 1200 * NSEC_PER_MSEC)
                    try Task.checkCancellation()
                } catch {
                    return
                }
                canActivateCommandClients = true
                updateCommandClients(connected: vpnController.isConnected, reason: "startupActivateClientsTask")
            }
        }
        .onChange(of: vpnController.isConnected) { connected in
            updateCommandClients(connected: connected, reason: "onChange(vpnController.isConnected)")
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                sceneTask?.cancel()
                sceneTask = Task {
                    NSLog("HomeTabView scenePhase active (before load). vpnConnected=%@", vpnController.isConnected.description)
                    do {
                        try await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
                        try Task.checkCancellation()
                    } catch {
                        return
                    }
                    await vpnController.load()
                    if Task.isCancelled { return }
                    NSLog("HomeTabView scenePhase active (after load). vpnConnected=%@ status=%ld", vpnController.isConnected.description, vpnController.status.rawValue)
                    await MainActor.run {
                        if Task.isCancelled { return }
                        if !canActivateCommandClients { canActivateCommandClients = true }
                        updateCommandClients(connected: vpnController.isConnected, reason: "scenePhaseActiveTask")
                    }
                }
            } else {
                NSLog(
                    "HomeTabView scenePhase %@ -> disconnect command clients (connected=%@ canActivate=%@)",
                    String(describing: phase),
                    vpnController.isConnected.description,
                    canActivateCommandClients.description
                )
                sceneTask?.cancel()
                startupLoadTask?.cancel()
                startupProfilesTask?.cancel()
                startupActivateClientsTask?.cancel()
                canActivateCommandClients = false
                statusClient.disconnect()
                groupClient.disconnect()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if !canActivateCommandClients {
                canActivateCommandClients = true
            }
            updateCommandClients(connected: vpnController.isConnected, reason: "UIApplication.didBecomeActive")
        }
        .onDisappear {
            sceneTask?.cancel()
            startupLoadTask?.cancel()
            startupProfilesTask?.cancel()
            startupActivateClientsTask?.cancel()
            canActivateCommandClients = false
            statusClient.disconnect()
            groupClient.disconnect()
        }
        .alert("请先设置供应商", isPresented: $showProviderRequiredAlert) {
            Button("去 Market") {
                onOpenMarket?()
            }
            Button("我知道了", role: .cancel) {}
        } message: {
            Text("当前未检测到可用供应商。请先前往 Market 安装或导入供应商配置。")
        }
    }

    private var connectionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("MeshFlux \(appVersion)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))

                    Spacer()

                    HStack(spacing: 6) {
                        StatusDot(isActive: vpnController.isConnected)
                        Text(vpnStatus)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(vpnController.isConnected ? Color(red: 0.0, green: 0.62, blue: 0.33) : Color.black.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                    )
                }

                Button {
                    Task { await toggleVPNWithGuard() }
                } label: {
                    HStack(spacing: 12) {
                        Image(vpnController.isConnected ? "stop_vpn" : "start_vpn")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(vpnController.isConnected ? "断开 VPN" : "连接 VPN")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text(vpnController.isConnected ? "点击后停止代理服务" : "点击后启动代理服务")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.88))
                        }
                        Spacer()
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: vpnController.isConnected
                                        ? [Color(red: 1.0, green: 0.52, blue: 0.26), Color(red: 0.95, green: 0.35, blue: 0.19)]
                                        : [Color(red: 0.11, green: 0.53, blue: 0.96), Color(red: 0.14, green: 0.74, blue: 0.96)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isVPNTransitioning)
            }
        }
    }

    private var merchantCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("流量商户")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.68))

                if profileList.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profileLoadError == nil ? "未安装供应商，请前往 Market 安装或导入。" : "加载失败：\(profileLoadError ?? "")")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Button("去 Market 设置供应商") {
                            onOpenMarket?()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Menu {
                        ForEach(profileList, id: \.mustID) { profile in
                            Button {
                                Task { await switchProfile(profile.mustID) }
                            } label: {
                                if profile.mustID == selectedProfileID {
                                    Label(profile.name, systemImage: "checkmark")
                                } else {
                                    Text(profile.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.rectangle.stack.fill")
                                .foregroundStyle(Color(red: 0.11, green: 0.53, blue: 0.96))
                            Text(selectedProfileName)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color(red: 0.60, green: 0.82, blue: 1.0).opacity(0.8), lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
    }

    private var trafficCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                    Text("流量")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.75))

                HStack(spacing: 10) {
                    scoreCell(title: "上行", value: totalUplinkText, tint: Color(red: 0.08, green: 0.50, blue: 0.95))
                    scoreCell(title: "下行", value: totalDownlinkText, tint: Color(red: 0.02, green: 0.70, blue: 0.52))
                }
            }
        }
    }

    private var outboundCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("节点")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.75))
                    Spacer()
                        if let delay = currentOutboundDelayText {
                            Text(delay)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.58))
                        }
                }

                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .foregroundStyle(Color.black.opacity(0.55))
                    Text(currentOutboundDisplay)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Task { await doURLTest() }
                    } label: {
                        if urlTesting {
                            ProgressView().tint(.orange)
                        } else {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(urlTesting || !vpnController.isConnected || currentGroup == nil)

                    Button {
                        showOutboundPicker = true
                    } label: {
                        Text("切换")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundColor(.white)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
                    }
                    .buttonStyle(.plain)
                    .disabled(!vpnController.isConnected || currentGroup?.items.isEmpty != false)
                }
            }
        }
        .opacity(vpnController.isConnected ? 1 : 0.75)
    }

    private func updateCommandClients(connected: Bool, reason: String) {
        guard canActivateCommandClients else {
            NSLog("HomeTabView updateCommandClients reason=%@ skip: canActivate=false -> disconnect", reason)
            statusClient.disconnect()
            groupClient.disconnect()
            return
        }
        let appState = UIApplication.shared.applicationState
        let shouldConnect = connected && appState == .active
        NSLog(
            "HomeTabView updateCommandClients reason=%@ connected=%@ scene=%@ appState=%ld shouldConnect=%@",
            reason,
            connected.description,
            String(describing: scenePhase),
            appState.rawValue,
            shouldConnect.description
        )
        if shouldConnect {
            statusClient.connect()
            groupClient.connect()
        } else {
            statusClient.disconnect()
            groupClient.disconnect()
        }
    }

    private func loadProfiles() async {
        await MainActor.run {
            profileLoadError = nil
        }
        do {
            let list = try await ProfileManager.list()

            var sid = await SharedPreferences.selectedProfileID.get()
            if list.isEmpty {
                sid = -1
                await SharedPreferences.selectedProfileID.set(-1)
            }
            if let first = list.first, sid < 0 {
                sid = first.mustID
                await SharedPreferences.selectedProfileID.set(sid)
            }
            if list.first(where: { $0.mustID == sid }) == nil, let first = list.first {
                sid = first.mustID
                await SharedPreferences.selectedProfileID.set(sid)
            }

            await MainActor.run {
                profileList = list
                selectedProfileID = sid
            }
        } catch {
            await MainActor.run {
                profileLoadError = error.localizedDescription
                profileList = []
            }
        }
    }

    private func switchProfile(_ newId: Int64) async {
        await MainActor.run {
            selectedProfileID = newId
        }
        await SharedPreferences.selectedProfileID.set(newId)
        if vpnController.isConnected {
            await vpnController.reconnectToApplySettings()
        }
    }

    private func doURLTest() async {
        guard let g = currentGroup else { return }
        urlTesting = true
        defer { urlTesting = false }
        do {
            try await groupClient.urlTest(groupTag: g.tag)
        } catch {
            NSLog("HomeTabView urltest failed: %@", String(describing: error))
        }
    }

    private func toggleVPNWithGuard() async {
        guard !isVPNTransitioning else { return }
        if !vpnController.isConnected && !hasUsableProvider {
            await MainActor.run {
                showProviderRequiredAlert = true
            }
            return
        }
        vpnActionBusy = true
        defer { vpnActionBusy = false }
        await vpnController.toggleVPNAsync()

        let deadline = Date().addingTimeInterval(18)
        while Date() < deadline {
            let s = vpnController.status
            if s != .connecting, s != .reasserting, s != .disconnecting {
                break
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func scoreCell(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.58))
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Pieces

private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.96), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 8)
    }
}

private struct StatusDot: View {
    let isActive: Bool
    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray.opacity(0.6))
            .frame(width: 8, height: 8)
    }
}

private struct OutboundPickerSheet: View {
    @EnvironmentObject private var vpnController: VPNController
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var groupClient: GroupCommandClient
    let groupTag: String?

    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var urlTesting = false
    @State private var testingNodeTag: String?
    @State private var testingMessage = "测速中，请稍候…"

    private var currentGroup: OutboundGroupModel? {
        if let groupTag, let byTag = groupClient.groups.first(where: { $0.tag == groupTag }) {
            return byTag
        }
        return groupClient.groups.first
    }

    var body: some View {
        ZStack {
            List {

                if let g = currentGroup {
                    Section("节点") {
                        ForEach(g.items) { item in
                            HStack {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.tag)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(item.type)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if g.selected == item.tag {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    if item.urlTestDelay > 0 {
                                        Text(item.delayString)
                                            .font(.caption)
                                            .foregroundColor(Color(red: item.delayColor.r, green: item.delayColor.g, blue: item.delayColor.b))
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await selectOutbound(group: g, item: item) }
                                }
                                
                                Button {
                                    Task { await doSingleURLTest(groupTag: g.tag, itemTag: item.tag) }
                                } label: {
                                    ZStack {
                                        if testingNodeTag == item.tag {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "bolt.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .frame(width: 44, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.orange.opacity(0.12))
                                    )
                                    .contentShape(Rectangle()) // 确保整个区域可点击
                                }
                                .buttonStyle(.plain)
                                .disabled(urlTesting || testingNodeTag != nil || !vpnController.isConnected)
                            }
                    }
                }
            } else {
                Section {
                    Text(vpnController.isConnected ? "暂无可用节点" : "请先连接 VPN")
                        .foregroundStyle(.secondary)
                }
                }
            }
            .disabled(urlTesting || testingNodeTag != nil)
            .navigationTitle("切换节点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await doURLTest() }
                    } label: {
                        Label("测速", systemImage: "bolt.fill")
                    }
                    .disabled(urlTesting || testingNodeTag != nil || !vpnController.isConnected || currentGroup == nil)
                }
            }
            .overlay {
                if urlTesting || testingNodeTag != nil {
                    ZStack {
                        Color.black.opacity(0.22)
                            .ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(1.1)
                            Text(testingMessage)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.68))
                        )
                    }
                    .transition(.opacity)
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func doURLTest() async {
        guard let g = currentGroup else { return }
        testingMessage = "正在测速节点…"
        let startedAt = Date()
        let before = snapshot(group: g)
        urlTesting = true
        defer { urlTesting = false }
        do {
            try await groupClient.urlTest(groupTag: g.tag)
            let updated = await waitForURLTestResult(groupTag: g.tag, before: before, targetTag: nil, minHold: startedAt)
            if !updated {
                await MainActor.run {
                    alertMessage = "已触发测速，但暂未收到延迟更新，请稍后再查看。"
                    showAlert = true
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func doSingleURLTest(groupTag: String, itemTag: String) async {
        guard vpnController.isConnected else { return }
        testingMessage = "正在测速 \(itemTag)…"
        let startedAt = Date()
        testingNodeTag = itemTag
        defer { testingNodeTag = nil }
        do {
            let before = snapshot(group: currentGroup)
            try await groupClient.urlTestSingle(groupTag: groupTag, outboundTag: itemTag)
            let updated = await waitForURLTestResult(groupTag: groupTag, before: before, targetTag: itemTag, minHold: startedAt)
            if !updated {
                await MainActor.run {
                    alertMessage = "已触发该节点测速，但暂未收到更新，请稍后再查看。"
                    showAlert = true
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func snapshot(group: OutboundGroupModel?) -> [String: (delay: UInt16, time: TimeInterval)] {
        guard let group else { return [:] }
        var map: [String: (delay: UInt16, time: TimeInterval)] = [:]
        for item in group.items {
            map[item.tag] = (item.urlTestDelay, item.urlTestTime.timeIntervalSince1970)
        }
        return map
    }

    private func waitForURLTestResult(
        groupTag: String,
        before: [String: (delay: UInt16, time: TimeInterval)],
        targetTag: String?,
        minHold: Date,
        timeoutSeconds: TimeInterval = 8
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var changed = false
        while Date() < deadline {
            if let group = groupClient.groups.first(where: { $0.tag == groupTag }) {
                if let targetTag {
                    if let item = group.items.first(where: { $0.tag == targetTag }) {
                        let prev = before[targetTag]
                        let nowTime = item.urlTestTime.timeIntervalSince1970
                        if prev == nil || item.urlTestDelay != prev?.delay || nowTime > (prev?.time ?? 0) {
                            changed = true
                            break
                        }
                    }
                } else {
                    changed = group.items.contains { item in
                        let prev = before[item.tag]
                        let nowTime = item.urlTestTime.timeIntervalSince1970
                        return prev == nil || item.urlTestDelay != prev?.delay || nowTime > (prev?.time ?? 0)
                    }
                    if changed { break }
                }
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
        }

        let remaining = 0.9 - Date().timeIntervalSince(minHold)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        return changed
    }

    private func selectOutbound(group g: OutboundGroupModel, item: OutboundGroupItemModel) async {
        guard vpnController.isConnected else { return }
        guard g.selectable else { return }
        if g.selected == item.tag { return }
        do {
            try await groupClient.selectOutbound(groupTag: g.tag, outboundTag: item.tag)
            groupClient.setSelected(groupTag: g.tag, outboundTag: item.tag)
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

struct HomeTabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            HomeTabView()
        }
        .environmentObject(VPNController())
    }
}
