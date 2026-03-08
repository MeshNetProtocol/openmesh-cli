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
    @Environment(\.colorScheme) private var scheme

    @StateObject private var statusClient = StatusCommandClient()
    @StateObject private var groupClient = GroupCommandClient()

    @State private var profileList: [Profile] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var profileLoadError: String?
    @State private var showProfileSelection = false
    @State private var selectedProviderHasUpdate = false

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
            MarketIOSTheme.windowBackground(scheme)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    merchantCard
                    if vpnController.isConnected {
                        trafficCard
                        outboundCard
                    }
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .disabled(isVPNTransitioning || showProfileSelection)
            .overlay {
                if showProfileSelection {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation { showProfileSelection = false }
                            }
                        
                        VStack(spacing: 0) {
                            HStack {
                                Text("选择供应商配置")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .kerning(0.5)
                                    .foregroundStyle(Color(red: 0.11, green: 0.53, blue: 0.96).opacity(0.6))
                                Spacer()
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showProfileSelection = false }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                        .padding(8)
                                        .background(Color.black.opacity(0.04))
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                            .padding(.bottom, 12)
                            
                            Divider()
                                .opacity(0.1)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                            
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(profileList, id: \.mustID) { profile in
                                        Button {
                                            withAnimation { showProfileSelection = false }
                                            Task { await switchProfile(profile.mustID) }
                                        } label: {
                                            HStack(spacing: 12) {
                                                // Indicator Bar
                                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                    .fill(profile.mustID == selectedProfileID ? Color(red: 0.11, green: 0.53, blue: 0.96) : Color.clear)
                                                    .frame(width: 4, height: 22)
                                                
                                                Text(profile.name)
                                                    .font(.system(size: 16, weight: profile.mustID == selectedProfileID ? .bold : .semibold, design: .rounded))
                                                    .foregroundStyle(profile.mustID == selectedProfileID ? Color(red: 0.11, green: 0.53, blue: 0.96) : Color.primary.opacity(0.7))
                                                
                                                Spacer()
                                                
                                                if profile.mustID == selectedProfileID {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .black))
                                                        .foregroundStyle(Color(red: 0.11, green: 0.53, blue: 0.96))
                                                        .padding(6)
                                                        .background(Color(red: 0.11, green: 0.53, blue: 0.96).opacity(0.1))
                                                        .clipShape(Circle())
                                                }
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(profile.mustID == selectedProfileID ? Color(red: 0.11, green: 0.53, blue: 0.96).opacity(0.12) : Color.black.opacity(0.04))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(profile.mustID == selectedProfileID ? Color(red: 0.11, green: 0.53, blue: 0.96).opacity(0.25) : Color.clear, lineWidth: 1.5)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                        }
                        .frame(maxWidth: 340)
                        .frame(maxHeight: 400)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .shadow(color: Color.black.opacity(0.2), radius: 20)
                        )
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    .zIndex(100)
                }

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
        .onReceive(NotificationCenter.default.publisher(for: MarketService.shared.providerUpdateStateDidChangeNotification)) { _ in
            Task { await refreshSelectedProviderUpdateFlag() }
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
        MFGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                MFHeaderSection(
                    eyebrow: "DASHBOARD",
                    title: hasUsableProvider
                        ? (vpnController.isConnected ? "连接已启用" : "准备连接")
                        : "先完成配置",
                    subtitle: hasUsableProvider
                        ? "当前供应商：\(selectedProfileName)"
                        : "先安装或导入供应商配置，再开始连接网络。",
                    badges: connectionBadges,
                    trailing: AnyView(
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
                )

                if hasUsableProvider {
                    MFPrimaryButton(isDisabled: isVPNTransitioning) {
                        Task { await toggleVPNWithGuard() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(vpnController.isConnected ? "stop_vpn" : "start_vpn")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(vpnController.isConnected ? "断开 VPN" : "连接 VPN")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                Text(vpnController.isConnected ? "点击后停止代理服务" : "点击后启动代理服务")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))
                            }

                            Spacer()

                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(minHeight: 64)
                    }
                } else {
                    MFPrimaryButton {
                        onOpenMarket?()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("前往 Market 配置供应商")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var merchantCard: some View {
        MFGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if profileList.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        MFHeaderSection(
                            eyebrow: "PROVIDER",
                            title: "开始配置供应商",
                            subtitle: profileLoadError == nil
                                ? "没有可用 provider 时，首页只保留下一步动作，不堆说明。"
                                : "加载 provider 失败，请先处理配置问题。",
                            badges: providerEmptyBadges
                        )

                        MFPrimaryButton {
                            onOpenMarket?()
                        } label: {
                            HStack {
                                Text("打开 Market")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                    }
                } else {
                    MFHeaderSection(
                        eyebrow: "PROVIDER",
                        title: selectedProfileName,
                        subtitle: selectedProviderHasUpdate
                            ? "当前配置可用，且有可更新内容。"
                            : "当前配置已就绪，可以直接连接或切换。",
                        badges: providerReadyBadges
                    )

                    MFSecondaryButton {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            showProfileSelection = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle.stack.fill")
                                .font(.system(size: 18, weight: .semibold))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("切换供应商")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Text("查看已安装配置并切换当前 provider")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedProviderHasUpdate {
                                MFStatusBadge(title: "可更新", tint: MarketIOSTheme.meshAmber)
                            }

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var trafficCard: some View {
        MFGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                MFHeaderSection(
                    eyebrow: "TRAFFIC",
                    title: "流量概览",
                    subtitle: "连接建立后再强调状态数据，首屏不让图表抢主路径。",
                    badges: [
                        MFHeaderBadge("已连接", tint: MarketIOSTheme.meshMint),
                        MFHeaderBadge("累计统计", tint: MarketIOSTheme.meshBlue),
                    ]
                )

                HStack(spacing: 10) {
                    MFMetricCard(title: "上行", value: totalUplinkText, tint: MarketIOSTheme.meshBlue)
                    MFMetricCard(title: "下行", value: totalDownlinkText, tint: MarketIOSTheme.meshMint)
                }
            }
        }
    }

    private var outboundCard: some View {
        MFGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                MFHeaderSection(
                    eyebrow: "OUTBOUND",
                    title: currentOutboundDisplay,
                    subtitle: "节点切换和测速收敛为连接后的工具操作。",
                    badges: outboundBadges
                )

                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(currentOutboundDisplay)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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

                    MFSecondaryButton(
                        isDisabled: !vpnController.isConnected || currentGroup?.items.isEmpty != false
                    ) {
                        showOutboundPicker = true
                    } label: {
                        Text("切换")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .frame(width: 84)
                }
            }
        }
        .opacity(vpnController.isConnected ? 1 : 0.75)
    }

    private var connectionBadges: [MFHeaderBadge] {
        var badges = [
            MFHeaderBadge(vpnStatus, tint: vpnController.isConnected ? MarketIOSTheme.meshMint : MarketIOSTheme.meshBlue),
            MFHeaderBadge("版本 \(appVersion)", tint: MarketIOSTheme.meshIndigo),
        ]
        badges.append(MFHeaderBadge(hasUsableProvider ? "Provider 已就绪" : "未配置 Provider", tint: hasUsableProvider ? MarketIOSTheme.meshCyan : MarketIOSTheme.meshAmber))
        return badges
    }

    private var providerEmptyBadges: [MFHeaderBadge] {
        if let profileLoadError, !profileLoadError.isEmpty {
            return [
                MFHeaderBadge("加载失败", tint: MarketIOSTheme.meshRed),
                MFHeaderBadge("前往 Market 处理", tint: MarketIOSTheme.meshAmber),
            ]
        }
        return [
            MFHeaderBadge("无可用配置", tint: MarketIOSTheme.meshAmber),
            MFHeaderBadge("支持安装与导入", tint: MarketIOSTheme.meshCyan),
        ]
    }

    private var providerReadyBadges: [MFHeaderBadge] {
        var badges = [MFHeaderBadge("已安装", tint: MarketIOSTheme.meshMint)]
        if selectedProviderHasUpdate {
            badges.append(MFHeaderBadge("存在更新", tint: MarketIOSTheme.meshAmber))
        }
        return badges
    }

    private var outboundBadges: [MFHeaderBadge] {
        var badges = [MFHeaderBadge("节点切换", tint: MarketIOSTheme.meshCyan)]
        if let delay = currentOutboundDelayText {
            badges.append(MFHeaderBadge(delay, tint: MarketIOSTheme.meshAmber))
        } else {
            badges.append(MFHeaderBadge("未测速", tint: MarketIOSTheme.meshIndigo))
        }
        return badges
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
            await refreshSelectedProviderUpdateFlag(profileID: sid)
        } catch {
            await MainActor.run {
                profileLoadError = error.localizedDescription
                profileList = []
            }
            await refreshSelectedProviderUpdateFlag(profileID: -1)
        }
    }

    private func switchProfile(_ newId: Int64) async {
        await MainActor.run {
            selectedProfileID = newId
        }
        await SharedPreferences.selectedProfileID.set(newId)
        await refreshSelectedProviderUpdateFlag(profileID: newId)
        if vpnController.isConnected {
            await vpnController.reconnectToApplySettings()
        }
    }

    private func refreshSelectedProviderUpdateFlag(profileID: Int64? = nil) async {
        let pid = profileID ?? selectedProfileID
        guard pid >= 0 else {
            NSLog("HomeTabView refreshSelectedProviderUpdateFlag: no selected profile")
            await MainActor.run { selectedProviderHasUpdate = false }
            return
        }
        let mapping = await SharedPreferences.installedProviderIDByProfile.get()
        let providerID = mapping[String(pid)] ?? ""
        guard !providerID.isEmpty else {
            NSLog("HomeTabView refreshSelectedProviderUpdateFlag: no provider mapping for profile=%lld", pid)
            await MainActor.run { selectedProviderHasUpdate = false }
            return
        }
        let updates = await SharedPreferences.providerUpdatesAvailable.get()
        let hasUpdate = updates[providerID] == true
        NSLog("HomeTabView refreshSelectedProviderUpdateFlag: profile=%lld provider=%@ hasUpdate=%@", pid, providerID, hasUpdate.description)
        await MainActor.run { selectedProviderHasUpdate = hasUpdate }
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

}

// MARK: - Pieces

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
