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
    @State private var vpnActionBusy = false
    @State private var canActivateCommandClients = false
    @State private var sceneTask: Task<Void, Never>?
    @State private var startupLoadTask: Task<Void, Never>?
    @State private var startupProfilesTask: Task<Void, Never>?
    @State private var startupActivateClientsTask: Task<Void, Never>?
    @State private var showProviderRequiredAlert = false

    private let onOpenBootstrap: (() -> Void)?
    private let onOpenMarket: (() -> Void)?
    private let onOpenImport: (() -> Void)?

    init(
        onOpenBootstrap: (() -> Void)? = nil,
        onOpenMarket: (() -> Void)? = nil,
        onOpenImport: (() -> Void)? = nil
    ) {
        self.onOpenBootstrap = onOpenBootstrap
        self.onOpenMarket = onOpenMarket
        self.onOpenImport = onOpenImport
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
                    if !hasUsableProvider {
                        bootstrapHintCard
                    }
                    if profileLoadError != nil {
                        merchantCard
                    }
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
                    ProfileSelectionOverlay(
                        profiles: profileList,
                        selectedProfileID: selectedProfileID,
                        onClose: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                showProfileSelection = false
                            }
                        },
                        onSelect: { newId in
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                showProfileSelection = false
                            }
                            Task { await switchProfile(newId) }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            Task { await loadProfiles() }
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
            VStack(alignment: .leading, spacing: hasUsableProvider ? 12 : 18) {
                if hasUsableProvider {
                    MFHeaderSection(
                        eyebrow: nil,
                        title: "VPN",
                        subtitle: nil,
                        badges: connectionBadges,
                        trailing: AnyView(
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                MarketIOSTheme.meshBlue.opacity(0.18),
                                                MarketIOSTheme.meshCyan.opacity(0.22),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Image("AppLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 34, height: 34)
                            }
                            .frame(width: 48, height: 48)
                        )
                    )

                    MFPrimaryButton(
                        isDisabled: isVPNTransitioning,
                        gradientColors: vpnController.isConnected
                            ? [MarketIOSTheme.meshAmber, MarketIOSTheme.meshRed]
                            : [MarketIOSTheme.meshBlue, MarketIOSTheme.meshCyan]
                    ) {
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
                        .frame(minHeight: 58)
                    }

                    providerSwitchRow
                } else {
                    VStack(spacing: 14) {
                        Text("GET STARTED")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .kerning(1.1)
                            .foregroundStyle(MarketIOSTheme.meshBlue.opacity(0.58))

                        Circle()
                            .fill(MarketIOSTheme.meshBlue.opacity(0.16))
                            .frame(width: 62, height: 62)
                            .overlay {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(MarketIOSTheme.meshBlue)
                            }

                        VStack(spacing: 5) {
                            Text("欢迎使用 MeshFlux")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("先添加一个可用配置，再开始连接。")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        bootstrapSteps

                        VStack(spacing: 12) {
                            MFPrimaryButton {
                                onOpenBootstrap?()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("开始配置向导")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                    Spacer()
                                }
                            }

                            Button {
                                onOpenImport?()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("直接导入配置")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    Spacer()
                                }
                                .foregroundStyle(MarketIOSTheme.meshBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.52))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(MarketIOSTheme.meshBlue.opacity(0.18), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var bootstrapHintCard: some View {
        MFGlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MarketIOSTheme.meshBlue)
                    .padding(.top, 2)

                Text("需要自行获取配置文件，来源包括社区、论坛或自建服务器。")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }

    private var merchantCard: some View {
        MFGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                MFHeaderSection(
                    eyebrow: "PROVIDER",
                    title: "供应商加载异常",
                    subtitle: "当前 provider 信息未能正确载入。你可以前往 Market 重新安装，或检查本地配置是否完整。",
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
        }
    }

    private var trafficCard: some View {
        MFGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("流量")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
                HStack(spacing: 10) {
                    Text("节点")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    if let delay = currentOutboundDelayText {
                        MFStatusBadge(title: delay, tint: MarketIOSTheme.meshAmber)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(currentOutboundDisplay)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer()

                    MFSecondaryButton(
                        isDisabled: !vpnController.isConnected || currentGroup?.items.isEmpty != false
                    ) {
                        showOutboundPicker = true
                    } label: {
                        Text("切换")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .frame(width: 72)
                }
            }
        }
        .opacity(vpnController.isConnected ? 1 : 0.75)
    }

    private var connectionBadges: [MFHeaderBadge] {
        [MFHeaderBadge("版本 \(appVersion)", tint: MarketIOSTheme.meshIndigo)]
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

    private var providerSwitchRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("供应商")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .kerning(0.4)
                    .foregroundStyle(MarketIOSTheme.meshBlue.opacity(0.56))

                if selectedProviderHasUpdate {
                    MFStatusBadge(title: "可更新", tint: MarketIOSTheme.meshAmber)
                }
            }

            MFSecondaryButton {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    showProfileSelection = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.system(size: 17, weight: .semibold))

                    Text(selectedProfileName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
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

    private var bootstrapSteps: some View {
        HStack(alignment: .center, spacing: 10) {
            bootstrapStep(number: "1", title: "查找", isActive: true)
            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 28, height: 1)
                .padding(.top, -16)
            bootstrapStep(number: "2", title: "安装", isActive: false)
            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 28, height: 1)
                .padding(.top, -16)
            bootstrapStep(number: "3", title: "连接", isActive: false)
        }
    }

    private func bootstrapStep(number: String, title: String, isActive: Bool) -> some View {
        VStack(spacing: 7) {
            Circle()
                .fill(isActive ? MarketIOSTheme.meshBlue : Color.secondary.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay {
                    Text(number)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.65))
                }

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
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
                            }
                            .disabled(urlTesting || !vpnController.isConnected)
                    }
                }
            } else {
                Section {
                    Text(vpnController.isConnected ? "暂无可用节点" : "请先连接 VPN")
                        .foregroundStyle(.secondary)
                }
                }
            }
            .disabled(urlTesting)
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
                    .disabled(urlTesting || !vpnController.isConnected || currentGroup == nil)
                }
            }
            .overlay {
                if urlTesting {
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

private struct ProfileSelectionOverlay: View {
    @Environment(\.colorScheme) private var scheme

    let profiles: [Profile]
    let selectedProfileID: Int64
    let onClose: () -> Void
    let onSelect: (Int64) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Spacer()
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.22))
                            .frame(width: 38, height: 5)
                        Spacer()
                    }
                    .padding(.top, 10)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("切换供应商")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text("从已安装配置中选择一个立即切换")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.045))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)

                    MFGlassCard(horizontalPadding: 14, verticalPadding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("已安装供应商")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .kerning(0.45)
                                    .foregroundStyle(MarketIOSTheme.meshBlue.opacity(0.76))

                                Spacer()

                                MFStatusBadge(title: "\(profiles.count) 个配置", tint: MarketIOSTheme.meshCyan)
                            }

                            VStack(spacing: 10) {
                                ForEach(profiles, id: \.mustID) { profile in
                                    profileRow(profile)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 16)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.white.opacity(scheme == .dark ? 0.10 : 0.32), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.20), radius: 22, x: 0, y: -4)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        let isSelected = profile.mustID == selectedProfileID

        return Button {
            onSelect(profile.mustID)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? MarketIOSTheme.meshBlue.opacity(0.16) : Color.black.opacity(0.035))
                        .frame(width: 42, height: 42)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(MarketIOSTheme.meshBlue)
                    } else {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(isSelected ? "当前使用中" : "点按切换到此供应商")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? MarketIOSTheme.meshBlue.opacity(0.92) : .secondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MarketIOSTheme.meshBlue)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? MarketIOSTheme.meshBlue.opacity(0.12) : Color.white.opacity(0.60))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? MarketIOSTheme.meshBlue.opacity(0.3) : Color.black.opacity(0.05), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
