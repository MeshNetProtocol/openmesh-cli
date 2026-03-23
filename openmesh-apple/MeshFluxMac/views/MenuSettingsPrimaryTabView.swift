import SwiftUI
import AppKit
import VPNLibrary
import OpenMeshGo

struct MenuSettingsPrimaryTabView: View {
    @ObservedObject var vpnController: VPNController

    let displayVersion: String

    let isLoadingProfiles: Bool
    let profileList: [ProfilePreview]
    @Binding var selectedProfileID: Int64
    @Binding var isReasserting: Bool

    let onLoadProfiles: () async -> Void
    let onSwitchProfile: (Int64) async -> Void

    @State private var windowPresenter = MenuSingleWindowPresenter()
    @StateObject private var nodeStore = MenuNodeStore()
    @StateObject private var statusClient = StatusCommandClient()

    @State private var uplinkKBps: Double = 0
    @State private var downlinkKBps: Double = 0
    @State private var uplinkKBpsSeries: [Double] = Array(repeating: 0, count: 36)
    @State private var downlinkKBpsSeries: [Double] = Array(repeating: 0, count: 36)
    @State private var seriesUp: [Double] = Array(repeating: 0, count: 12)
    @State private var seriesDown: [Double] = Array(repeating: 0, count: 12)
    @State private var uplinkTotalBytes: Int64 = 0
    @State private var downlinkTotalBytes: Int64 = 0
    @State private var offlineNodes: [MenuNodeCandidate] = []
    @State private var offlineSelectedNodeID: String = ""
    @State private var offlineGroupTag: String = "proxy"
    @State private var optimisticShowStop = false
    @State private var isMenuVisible = false
    @State private var shouldShowUpdateButton = false
    @State private var updateProviderID: String = ""
    @State private var updateLocalHash: String = ""
    @State private var updateRemoteHash: String = ""
    @State private var isUpdatingProvider = false
    @State private var shouldShowInitButton = false
    @State private var initPendingTags: [String] = []
    @State private var showProfilePopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topControlAndProfile
            Divider().opacity(0.55)
            if vpnController.isConnected {
                trafficCard
            } else if shouldShowBootstrapGuidance {
                VStack(spacing: 10) {
                    bootstrapGuidanceCard
                    bootstrapHintCard
                }
            }
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.top, 4)
        .background {
            MeshFluxWindowBackground()
        }
        .task {
            if isLoadingProfiles {
                await onLoadProfiles()
            }
        }
        .onAppear {
            isMenuVisible = true
            refreshClientSubscriptions()
        }
        .onDisappear {
            isMenuVisible = false
            refreshClientSubscriptions()
        }
        .onChange(of: vpnController.isConnecting) { _ in
            clearOptimisticStateIfNeeded()
        }
        .onChange(of: vpnController.isConnected) { _ in
            clearOptimisticStateIfNeeded()
            refreshClientSubscriptions()
            if !vpnController.isConnected {
                resetTrafficSeries()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuDetachedWindowsChanged)) { _ in
            refreshClientSubscriptions()
        }
        .onReceive(statusClient.$status) { status in
            applyStatus(status)
        }
        .onChange(of: selectedProfileID) { _ in
            loadOfflineNodesFromProfile()
            Task { await refreshUpdateAvailability() }
        }
        .onChange(of: profileList) { _ in
            loadOfflineNodesFromProfile()
            Task { await refreshUpdateAvailability() }
        }
        .task {
            loadOfflineNodesFromProfile()
            await refreshUpdateAvailability()
        }
    }

    private var vendorName: String {
        if let match = merchantProfiles.first(where: { $0.id == selectedProfileID }) {
            return match.name
        }
        return "请选择供应商"
    }

    private var selectedMerchantName: String {
        merchantProfiles.first(where: { $0.id == selectedProfileID })?.name ?? "请选择供应商"
    }

    private var merchantProfiles: [ProfilePreview] {
        profileList
    }

    private var shouldShowBootstrapGuidance: Bool {
        !vpnController.isConnected && !vpnController.isConnecting && merchantProfiles.isEmpty
    }

    private var bootstrapGuidanceCard: some View {
        VStack(spacing: 18) {
            Text("GET STARTED")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .kerning(1.1)
                .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.55))

            Circle()
                .fill(Color(red: 0.78, green: 0.86, blue: 0.96).opacity(0.64))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                }

            Text("欢迎使用 MeshFlux")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.18))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            bootstrapSteps

            VStack(spacing: 12) {
                    Button {
                        closeVisibleMenuBarExtraWindow()
                        BootstrapFetchWindowManager.shared.show(
                            onImportConfig: {
                                BootstrapFetchWindowManager.shared.close()
                                OfflineImportWindowManager.shared.show()
                            },
                            onInstallResolvedConfig: {
                                Task { await refreshUpdateAvailability() }
                            }
                        )
                    } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("开始配置向导")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(MeshFluxTheme.meshBlue)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    OfflineImportWindowManager.shared.show()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("直接导入配置")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(red: 0.22, green: 0.28, blue: 0.36))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.82))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(red: 0.83, green: 0.86, blue: 0.90), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.97, blue: 0.99),
                            Color(red: 0.94, green: 0.96, blue: 0.99)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 0.76, green: 0.83, blue: 0.93), lineWidth: 1.4)
                }
        }
    }

    private var bootstrapHintCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MeshFluxTheme.meshBlue)
                .padding(.top, 2)

            Text("提示：需要自行获取配置文件，来源包括社区、论坛或自建服务器。")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.21, green: 0.26, blue: 0.34))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.96, green: 0.97, blue: 0.99))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.82, green: 0.86, blue: 0.93), lineWidth: 1)
                }
        }
    }

    private var bootstrapSteps: some View {
        HStack(alignment: .center, spacing: 10) {
            bootstrapStep(number: "1", title: "查找", isActive: true)
            Rectangle()
                .fill(Color(red: 0.75, green: 0.78, blue: 0.83))
                .frame(width: 34, height: 1)
                .padding(.top, -20)
            bootstrapStep(number: "2", title: "安装", isActive: false)
            Rectangle()
                .fill(Color(red: 0.75, green: 0.78, blue: 0.83))
                .frame(width: 34, height: 1)
                .padding(.top, -20)
            bootstrapStep(number: "3", title: "连接", isActive: false)
        }
    }

    private func bootstrapStep(number: String, title: String, isActive: Bool) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(isActive ? MeshFluxTheme.meshBlue : Color(red: 0.86, green: 0.88, blue: 0.91))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(number)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isActive ? .white : Color(red: 0.34, green: 0.38, blue: 0.45))
                }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.21, green: 0.26, blue: 0.34))
        }
    }


    private var topControlAndProfile: some View {
        VStack {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        toggleVPNFromHeader()
                    } label: {
                        vpnActionImage(
                            assetName: vpnButtonShowsStop ? "stop_vpn" : "start_vpn",
                            fallbackSystemName: vpnButtonShowsStop ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vpnController.isConnecting)
                    .opacity(vpnController.isConnecting ? 0.65 : 1.0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MeshFlux")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(red: 0.10, green: 0.14, blue: 0.20))
                        Text(displayVersion)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.41, green: 0.45, blue: 0.52))
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(vpnController.isConnected ? MeshFluxTheme.meshMint : Color(red: 0.20, green: 0.22, blue: 0.26))
                                .frame(width: 7, height: 7)
                            Text(connectionStatusText)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 0.20, green: 0.22, blue: 0.26))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill((vpnController.isConnected ? MeshFluxTheme.meshMint : Color.gray).opacity(0.12))
                        }
                        
                        if !vpnController.connectHint.isEmpty, !vpnController.isConnecting, !vpnController.isConnected {
                            Text(vpnController.connectHint)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.95))
                        }
                    }
                }

                Spacer(minLength: 10)
                profilePickerCompact
                    .frame(maxWidth: 190, alignment: .leading)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.97, blue: 0.99),
                            Color(red: 0.93, green: 0.95, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(MeshFluxTheme.meshCyan.opacity(0.10))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)
                        .offset(x: 18, y: -20)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 0.82, green: 0.86, blue: 0.91), lineWidth: 1.1)
                }
        }
    }

    private var vpnButtonShowsStop: Bool {
        optimisticShowStop || vpnController.isConnecting || vpnController.isConnected
    }

    private var connectionStatusText: String {
        if vpnController.isConnecting { return "连接中…" }
        return vpnController.isConnected ? "已连接" : "未连接"
    }

    private var canOptimisticallyStartVPN: Bool {
        selectedProfileID >= 0 && !merchantProfiles.isEmpty
    }

    private func toggleVPNFromHeader() {
        if vpnButtonShowsStop {
            optimisticShowStop = false
        } else if canOptimisticallyStartVPN {
            optimisticShowStop = true
        } else {
            optimisticShowStop = false
        }
        vpnController.toggleVPN()
    }

    private func clearOptimisticStateIfNeeded() {
        if !vpnController.isConnecting, !vpnController.isConnected {
            optimisticShowStop = false
        }
    }

    private func vpnActionImage(assetName: String, fallbackSystemName: String) -> some View {
        let ns = NSImage(named: assetName)
        return Group {
            if let ns {
                Image(nsImage: ns)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 34, height: 34)
        .padding(6)
        .background {
            MeshFluxCard(cornerRadius: 12) { Color.clear }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var profilePickerCompact: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前配置")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.42, blue: 0.48))

            if isLoadingProfiles {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("加载中…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if merchantProfiles.isEmpty {
                Text("请先去流量市场选择流量供应商")
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.9))
            } else {
                HStack(spacing: 8) {
                    merchantMenuButton
                    if shouldShowInitButton {
                        Button("Init") {
                            if vpnController.isConnected {
                                Task {
                                    let changed = await MarketService.shared.initializePendingRuleSetsForSelectedProfile()
                                    if changed {
                                        vpnController.requestExtensionReload()
                                    }
                                    await refreshUpdateAvailability()
                                }
                            } else {
                                vpnController.toggleVPN()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if shouldShowUpdateButton {
                        Button("Update") {
                            guard !updateProviderID.isEmpty else { return }
                            Task {
                                let providers = (try? await MarketService.shared.fetchMarketProvidersCached()) ?? []
                                guard let provider = providers.first(where: { $0.id == updateProviderID }) else {
                                    await MainActor.run {
                                        isUpdatingProvider = false
                                    }
                                    return
                                }
                                await MainActor.run {
                                    ProviderInstallWindowManager.shared.show(provider: provider) { isInstalling in
                                        isUpdatingProvider = isInstalling
                                        if !isInstalling {
                                            Task { await refreshUpdateAvailability() }
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .disabled(isReasserting || vpnController.isConnecting || isLoadingProfiles || isUpdatingProvider)
                .opacity(isReasserting || vpnController.isConnecting || isLoadingProfiles || isUpdatingProvider ? 0.65 : 1.0)
            }
        }
    }

    private func refreshUpdateAvailability() async {
        guard selectedProfileID >= 0 else {
            await MainActor.run {
                shouldShowUpdateButton = false
                shouldShowInitButton = false
                initPendingTags = []
                updateProviderID = ""
                updateLocalHash = ""
                updateRemoteHash = ""
            }
            return
        }
        if merchantProfiles.first(where: { $0.id == selectedProfileID }) == nil {
            await MainActor.run {
                shouldShowUpdateButton = false
                shouldShowInitButton = false
                initPendingTags = []
                updateProviderID = ""
                updateLocalHash = ""
                updateRemoteHash = ""
            }
            return
        }

        let mapping = await SharedPreferences.installedProviderIDByProfile.get()
        guard let providerID = mapping[String(selectedProfileID)], !providerID.isEmpty else {
            await MainActor.run {
                shouldShowUpdateButton = false
                shouldShowInitButton = false
                initPendingTags = []
                updateProviderID = ""
                updateLocalHash = ""
                updateRemoteHash = ""
            }
            return
        }

        let localHashes = await SharedPreferences.installedProviderPackageHash.get()
        let localHash = localHashes[providerID] ?? ""
        guard !localHash.isEmpty else {
            await MainActor.run {
                shouldShowUpdateButton = false
                shouldShowInitButton = false
                initPendingTags = []
                updateProviderID = ""
                updateLocalHash = ""
                updateRemoteHash = ""
            }
            return
        }

        let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
        let pendingTags = pending[providerID] ?? []

        let providers = (try? await MarketService.shared.fetchMarketProvidersCached()) ?? []
        let remoteHash = providers.first(where: { $0.id == providerID })?.package_hash ?? ""
        let needsUpdate = !remoteHash.isEmpty && remoteHash != localHash

        await MainActor.run {
            shouldShowUpdateButton = needsUpdate
            shouldShowInitButton = !pendingTags.isEmpty
            initPendingTags = pendingTags
            updateProviderID = providerID
            updateLocalHash = localHash
            updateRemoteHash = remoteHash
        }
    }

    private var merchantMenuButton: some View {
        Button {
            showProfilePopover = true
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedMerchantName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.28))
                        .lineLimit(1)
                    Text("点击切换")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(red: 0.54, green: 0.57, blue: 0.62))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.85))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.96, blue: 0.99))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color(red: 0.84, green: 0.88, blue: 0.95), lineWidth: 0.9)
                    }
            }
        }
        .buttonStyle(ProviderTriggerButtonStyle())
        .popover(isPresented: $showProfilePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择供应商")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.26))
                    Text("当前配置将用于连接与节点切换")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)

                Divider()
                    .opacity(0.14)
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("已安装供应商")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.55))
                        .padding(.horizontal, 10)

                    ForEach(merchantProfiles) { p in
                        Button {
                            selectedProfileID = p.id
                            isReasserting = true
                            showProfilePopover = false
                            Task { await onSwitchProfile(p.id) }
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(p.id == selectedProfileID ? MeshFluxTheme.meshBlue : Color.clear)
                                    .frame(width: 3, height: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.name)
                                        .font(.system(size: 13, weight: p.id == selectedProfileID ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(p.id == selectedProfileID ? Color(red: 0.14, green: 0.18, blue: 0.24) : Color.primary.opacity(0.78))
                                        .lineLimit(1)
                                    Text(p.id == selectedProfileID ? "当前使用中" : "点击切换到该供应商")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if p.id == selectedProfileID {
                                    ZStack {
                                        Circle()
                                            .fill(MeshFluxTheme.meshBlue.opacity(0.14))
                                            .frame(width: 24, height: 24)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(MeshFluxTheme.meshBlue)
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(p.id == selectedProfileID ? MeshFluxTheme.meshBlue.opacity(0.09) : Color.white.opacity(0.08))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(p.id == selectedProfileID ? MeshFluxTheme.meshBlue.opacity(0.14) : Color.white.opacity(0.10), lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(ProfileItemButtonStyle())
                    }
                }
            }
            .padding(10)
            .frame(minWidth: 280)
            .background(.ultraThinMaterial)
        }
    }

    private var trafficCard: some View {
        MenuCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Traffic")
                            .font(.system(size: 15, weight: .bold))
                        Text("实时吞吐与累计流量")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    moreInfoButton
                }

                trafficLegend

                MiniTrafficChart(upSeries: uplinkKBpsSeries, downSeries: downlinkKBpsSeries)
                    .frame(height: 80)

                Divider().opacity(0.35)

                nodeTrafficPanel
                    .padding(.top, 6)
            }
        }
    }

    private var nodeTrafficPanel: some View {
        VStack(spacing: 0) {
            nodeTrafficRowContent
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            MeshFluxTheme.techCardBackground(scheme: .light, glowColor: MeshFluxTheme.meshBlue.opacity(0.14))
        }
    }

    private var nodeTrafficRowContent: some View {
        let node = nodeStore.selectedNode
        let nodeName = node?.name ?? (nodeStore.selectedNodeID.isEmpty ? "—" : nodeStore.selectedNodeID)
        let nodeAddress = node?.address ?? "—"
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MeshFluxTheme.meshBlue.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current Node")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(nodeName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(nodeAddress)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                if vpnController.isConnected {
                    Button {
                        windowPresenter.showNodePicker(vendorName: vendorName, store: nodeStore, vpnController: vpnController)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 11, weight: .bold))
                            Text("切换节点")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.20))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(MeshFluxTheme.meshBlue.opacity(0.15), lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                        .font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("UPLINK")
                        .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(formatKBps(uplinkKBps))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(MeshFluxTheme.meshMint)
                        .font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DOWNLINK")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(formatKBps(downlinkKBps))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                openExternalURL("https://github.com/MeshNetProtocol/openmesh-cli")
            } label: {
                toolbarIconLabel(systemName: "wrench.and.screwdriver")
            }
            .buttonStyle(.plain)
            .help("Source Code")

            Button {
                openExternalURL("https://meshnetprotocol.github.io/")
            } label: {
                toolbarIconLabel(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .help("About MeshNet Protocol")

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                toolbarIconLabel(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("退出")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                }
        }
        .padding(.top, 4)
    }

    private func openExternalURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func formatKBps(_ value: Double) -> String {
        if value >= 1024 {
            return String(format: "%.1f MB/s", value / 1024.0)
        }
        if value >= 10 {
            return String(format: "%.0f KB/s", value)
        }
        return String(format: "%.1f KB/s", value)
    }

    private func updateLiveClients(isConnected: Bool) {
        if isConnected {
            statusClient.connect()
        } else {
            statusClient.disconnect()
        }
        // Node switching + offline RTT must be stable even when disconnected.
        applyOfflineNodesToStore()
    }

    private func refreshClientSubscriptions() {
        let shouldConnectLiveClients = vpnController.isConnected && (isMenuVisible || windowPresenter.hasDetachedWindows)
        updateLiveClients(isConnected: shouldConnectLiveClients)
    }

    private func applyStatus(_ status: OMLibboxStatusMessage?) {
        guard let status, status.trafficAvailable else {
            uplinkKBps = 0
            downlinkKBps = 0
            uplinkTotalBytes = 0
            downlinkTotalBytes = 0
            windowPresenter.updateTrafficMoreInfo(
                seriesUp: uplinkKBpsSeries,
                seriesDown: downlinkKBpsSeries,
                upKBps: uplinkKBps,
                downKBps: downlinkKBps,
                upTotalBytes: uplinkTotalBytes,
                downTotalBytes: downlinkTotalBytes
            )
            return
        }
        let upKBps = Double(status.uplink) / 1024.0
        let downKBps = Double(status.downlink) / 1024.0
        uplinkKBps = upKBps
        downlinkKBps = downKBps
        appendTrafficRateSample(upKBps: upKBps, downKBps: downKBps)
        uplinkTotalBytes = status.uplinkTotal
        downlinkTotalBytes = status.downlinkTotal
        let upTotalGB = Double(status.uplinkTotal) / 1_073_741_824.0
        let downTotalGB = Double(status.downlinkTotal) / 1_073_741_824.0
        appendTrafficTotalSample(upTotalGB: upTotalGB, downTotalGB: downTotalGB)
        windowPresenter.updateTrafficMoreInfo(
            seriesUp: uplinkKBpsSeries,
            seriesDown: downlinkKBpsSeries,
            upKBps: uplinkKBps,
            downKBps: downlinkKBps,
            upTotalBytes: uplinkTotalBytes,
            downTotalBytes: downlinkTotalBytes
        )
    }

    private func appendTrafficRateSample(upKBps: Double, downKBps: Double) {
        let cap = 36
        uplinkKBpsSeries.append(upKBps)
        downlinkKBpsSeries.append(downKBps)
        if uplinkKBpsSeries.count > cap { uplinkKBpsSeries.removeFirst(uplinkKBpsSeries.count - cap) }
        if downlinkKBpsSeries.count > cap { downlinkKBpsSeries.removeFirst(downlinkKBpsSeries.count - cap) }
    }

    private func appendTrafficTotalSample(upTotalGB: Double, downTotalGB: Double) {
        let cap = 12
        seriesUp.append(upTotalGB)
        seriesDown.append(downTotalGB)
        if seriesUp.count > cap { seriesUp.removeFirst(seriesUp.count - cap) }
        if seriesDown.count > cap { seriesDown.removeFirst(seriesDown.count - cap) }
    }

    private func resetTrafficSeries() {
        uplinkKBps = 0
        downlinkKBps = 0
        uplinkKBpsSeries = Array(repeating: 0, count: 36)
        downlinkKBpsSeries = Array(repeating: 0, count: 36)
        uplinkTotalBytes = 0
        downlinkTotalBytes = 0
        seriesUp = Array(repeating: 0, count: 12)
        seriesDown = Array(repeating: 0, count: 12)
    }

    private var trafficLegend: some View {
        HStack(spacing: 12) {
            legendItem(color: MeshFluxTheme.meshBlue, title: "UPLOAD", value: OMLibboxFormatBytes(uplinkTotalBytes))
            legendItem(color: MeshFluxTheme.meshMint, title: "DOWNLOAD", value: OMLibboxFormatBytes(downlinkTotalBytes))
        }
    }

    private var moreInfoButton: some View {
        Button {
            windowPresenter.showTrafficMoreInfo(
                seriesUp: uplinkKBpsSeries,
                seriesDown: downlinkKBpsSeries,
                upKBps: uplinkKBps,
                downKBps: downlinkKBps,
                upTotalBytes: uplinkTotalBytes,
                downTotalBytes: downlinkTotalBytes
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 10, weight: .semibold))
                Text("View details")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(MeshFluxTheme.meshBlue.opacity(0.14), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func legendItem(color: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.45), radius: 2)

                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private func toolbarIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.28))
            .frame(width: 32, height: 32)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    }
            }
    }

    private func loadOfflineNodesFromProfile() {
        guard let selected = profileList.first(where: { $0.id == selectedProfileID }) else {
            offlineNodes = []
            offlineSelectedNodeID = ""
            applyOfflineNodesToStore()
            return
        }
        let profileID = selectedProfileID
        Task {
            let parsed = (try? parseOfflineNodes(from: selected.origin.read())) ?? ([], "", [String: MenuNodeCandidate](), "proxy")
            let preferred = await preferredOutboundTag(profileID: profileID)
            let preferredSelected = {
                guard let preferred, parsed.2[preferred] != nil else { return parsed.1 }
                return preferred
            }()
            await MainActor.run {
                offlineNodes = parsed.0
                offlineSelectedNodeID = preferredSelected
                offlineGroupTag = parsed.3
                applyOfflineNodesToStore()
            }
        }
    }

    private func applyOfflineNodesToStore() {
        let profileID = selectedProfileID
        nodeStore.setOfflineNodes(
            offlineNodes,
            selectedNodeID: offlineSelectedNodeID,
            onSelectOffline: { outboundTag in
                let previous = offlineSelectedNodeID
                offlineSelectedNodeID = outboundTag
                Task {
                    await savePreferredOutboundTag(profileID: profileID, outboundTag: outboundTag)
                    if vpnController.isConnected {
                        do {
                            // Apply immediately inside the extension (durable via cache_file).
                            try await vpnController.requestSelectOutbound(groupTag: offlineGroupTag, outboundTag: outboundTag)
                        } catch {
                            await MainActor.run {
                                // Revert UI selection on failure (avoid "selected but not effective").
                                offlineSelectedNodeID = previous
                                nodeStore.selectedNodeID = previous
                                nodeStore.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        )
        if vpnController.isConnected {
            nodeStore.setURLTestProvider {
                try await vpnController.requestURLTest()
            }
        } else {
            nodeStore.setURLTestProvider(onURLTest: nil)
        }
    }

    private func preferredOutboundTag(profileID: Int64) async -> String? {
        let map = await SharedPreferences.selectedOutboundTagByProfile.get()
        return map["\(profileID)"]
    }

    private func savePreferredOutboundTag(profileID: Int64, outboundTag: String) async {
        var map = await SharedPreferences.selectedOutboundTagByProfile.get()
        if outboundTag.isEmpty {
            map.removeValue(forKey: "\(profileID)")
        } else {
            map["\(profileID)"] = outboundTag
        }
        await SharedPreferences.selectedOutboundTagByProfile.set(map)
    }

    private func parseOfflineNodes(from jsonText: String) throws -> ([MenuNodeCandidate], String, [String: MenuNodeCandidate], String) {
        guard let data = jsonText.data(using: .utf8) else { return ([], "", [:], "proxy") }
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let config = obj as? [String: Any] else { return ([], "", [:], "proxy") }
        let outbounds = (config["outbounds"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        var byTag: [String: MenuNodeCandidate] = [:]
        var ordered: [MenuNodeCandidate] = []

        func intValue(_ v: Any?) -> Int? {
            if let i = v as? Int { return i }
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String { return Int(s) }
            return nil
        }

        for outbound in outbounds {
            guard (outbound["type"] as? String) == "shadowsocks" else { continue }
            guard let tag = outbound["tag"] as? String, !tag.isEmpty else { continue }
            let server = (outbound["server"] as? String) ?? "—"
            let port = intValue(outbound["server_port"]) ?? intValue(outbound["port"])
            let node = MenuNodeCandidate(id: tag, name: tag, address: server, port: port, region: "-", latencyMs: nil)
            byTag[tag] = node
            ordered.append(node)
        }
        let selector = outbounds.first {
            let t = ($0["type"] as? String)?.lowercased() ?? ""
            let tag = ($0["tag"] as? String)?.lowercased() ?? ""
            return (t == "selector" || t == "urltest") && (tag == "proxy" || tag == "auto")
        } ?? outbounds.first {
            let t = ($0["type"] as? String)?.lowercased() ?? ""
            return t == "selector" || t == "urltest"
        }
        let defaultTag = (selector?["default"] as? String) ?? ordered.first?.id ?? ""
        let groupTag = (selector?["tag"] as? String) ?? "proxy"
        return (ordered, defaultTag, byTag, groupTag)
    }
}

struct BootstrapFetchWizardView: View {
    private enum SourceStatus {
        case waiting
        case searching
        case found
        case failed
    }

    private enum SourceKind {
        case github
        case community
        case privateNode
    }

    private struct SourceItem: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let endpoint: String
        let kind: SourceKind
        var status: SourceStatus = .waiting
        var payloadText: String?
        var byteCount: Int?
        var message: String = "等待开始"
        var errorDetail: String?
    }

    @State private var progress: Double = 0
    @State private var isSearching = false
    @State private var hasCompletedSearch = false
    @State private var selectedSourceID: UUID?
    @State private var searchTask: Task<Void, Never>?
    @State private var didStartSearch = false
    @State private var installError: String?
    @State private var sources: [SourceItem] = [
        .init(name: "GitHub 公共仓库", detail: "搜索开源配置文件", endpoint: "https://meshnetprotocol.github.io/bootstrap.json", kind: .github),
        .init(name: "开发者社区", detail: "扫描社区共享配置", endpoint: "https://gist.githubusercontent.com/hopwesley/3d3c35ef2dff6f4762f30e1df958f57b/raw/bootstrap.json", kind: .community),
        .init(name: "私人节点", detail: "检查私人节点配置", endpoint: "http://35.247.142.146:7788/api/bootstrap.json", kind: .privateNode),
    ]

    let onImportConfig: () -> Void
    let onInstallResolvedConfig: () -> Void
    let onClose: () -> Void

    private var foundCount: Int {
        sources.filter { $0.status == .found }.count
    }

    private var progressPercentText: String {
        "\(Int(progress * 100))%"
    }

    private var headerDescription: String {
        if hasCompletedSearch {
            if foundCount > 0 {
                return "找到 \(foundCount) 个可用配置来源，选择一个开始安装"
            }
            return "未找到可用配置来源，请重试下载或导入本地配置"
        }
        return "正在从多个来源搜索可用的配置文件..."
    }

    private var selectedSource: SourceItem? {
        guard let selectedSourceID else { return nil }
        return sources.first(where: { $0.id == selectedSourceID })
    }

    private var hasAvailableSource: Bool {
        foundCount > 0
    }

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        setupWindowTitleBar
                        setupContent
                    }
                }
                .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 12)
        }
        .frame(width: 620, height: 660)
        .onAppear {
            guard !didStartSearch else { return }
            didStartSearch = true
            startRealSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var setupWindowTitleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.94, green: 0.27, blue: 0.27)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.20)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 11, height: 11)
            }

            Text("配置设置向导")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(red: 0.95, green: 0.96, blue: 0.97))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.90, green: 0.91, blue: 0.93))
                .frame(height: 1)
        }
    }

    private var setupContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MeshFluxTheme.meshBlue, Color(red: 0.15, green: 0.55, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .shadow(color: MeshFluxTheme.meshBlue.opacity(0.22), radius: 12, x: 0, y: 8)
                        .overlay {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                        }

                    Text("查找可用配置")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.12))

                    Text(headerDescription)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 18)

                if isSearching {
                    VStack(spacing: 8) {
                        HStack {
                            Text("搜索进度")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.20, green: 0.23, blue: 0.29))
                            Spacer()
                            Text(progressPercentText)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(MeshFluxTheme.meshBlue)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(Color(red: 0.92, green: 0.93, blue: 0.95))
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [MeshFluxTheme.meshBlue, Color(red: 0.21, green: 0.60, blue: 0.98)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geo.size.width * progress))
                                    .animation(.easeInOut(duration: 0.25), value: progress)
                            }
                        }
                        .frame(height: 8)

                        Text("请稍候，正在扫描配置来源...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.50, green: 0.53, blue: 0.58))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                } else {
                    Spacer().frame(height: 20)
                }

                VStack(spacing: 10) {
                    ForEach(sources) { source in
                        sourceCard(source)
                    }
                }

                if hasCompletedSearch {
                    infoCard
                        .padding(.top, 12)
                }

                if let installError, !installError.isEmpty {
                    errorCard(installError)
                        .padding(.top, 10)
                }

                Spacer(minLength: 12)

                bottomActions
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: 548)
            .padding(.horizontal, 22)
        }
    }

    private func sourceCard(_ source: SourceItem) -> some View {
        let colors = sourceColors(for: source)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.iconBackground)
                    .frame(width: 42, height: 42)
                sourceIcon(for: source)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.12))

                    if source.status == .found {
                        Text("可用")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.06, green: 0.73, blue: 0.50))
                            .clipShape(Capsule())
                    }
                }

                Text(source.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))

                Text(source.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(source.status == .failed ? Color.red.opacity(0.8) : Color(red: 0.50, green: 0.53, blue: 0.58))

                if let errorDetail = source.errorDetail, source.status == .failed {
                    Text(errorDetail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.red.opacity(0.68))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            switch source.status {
            case .waiting:
                Text("等待中")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.60, green: 0.63, blue: 0.68))
            case .searching:
                ProgressView()
                    .controlSize(.small)
            case .found:
                Button {
                    selectedSourceID = source.id
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedSourceID == source.id ? "已选择" : "选择")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(MeshFluxTheme.meshBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            case .failed:
                Text("失败")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.75))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(colors.border, lineWidth: 2)
                }
        )
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MeshFluxTheme.meshBlue)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("配置文件包含什么？")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.12))
                Text("配置文件包含服务器地址、端口、加密方式等信息。选择后会自动导入并可立即使用。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(red: 0.36, green: 0.41, blue: 0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.94, green: 0.97, blue: 1.00))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.78, green: 0.87, blue: 1.00), lineWidth: 1.5)
                }
        )
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.72, green: 0.22, blue: 0.28))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 1.0, green: 0.95, blue: 0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.96, green: 0.78, blue: 0.82), lineWidth: 1)
                }
        )
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            if isSearching {
                wizardActionButton(title: "取消", systemImage: nil, style: .secondaryFill, action: cancelSearch)
            } else if hasAvailableSource {
                wizardActionButton(title: "取消安装", systemImage: nil, style: .secondaryFill, action: onClose)
            } else {
                wizardActionButton(title: "关闭", systemImage: nil, style: .secondaryFill, action: onClose)
            }
            wizardActionButton(title: "导入本地配置", systemImage: "square.and.arrow.up", style: .outlined, action: onImportConfig)
            if isSearching {
                wizardActionButton(title: "搜索中", systemImage: nil, style: .disabled, action: {})
                    .disabled(true)
            } else if hasAvailableSource {
                wizardActionButton(title: "安装选中配置", systemImage: nil, style: .primary, action: installSelectedSource)
                    .disabled(selectedSource == nil)
            } else if hasCompletedSearch {
                wizardActionButton(title: "重试下载", systemImage: "arrow.clockwise", style: .primary, action: startRealSearch)
            }
        }
    }

    private enum WizardButtonStyle {
        case secondaryFill
        case outlined
        case primary
        case disabled
    }

    private func wizardActionButton(title: String, systemImage: String?, style: WizardButtonStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(buttonForeground(style))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(buttonBackground(style))
            .overlay(buttonOverlay(style))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: style == .primary ? MeshFluxTheme.meshBlue.opacity(0.24) : .clear, radius: 8, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func buttonForeground(_ style: WizardButtonStyle) -> Color {
        switch style {
        case .primary:
            return .white
        case .disabled:
            return Color.white.opacity(0.85)
        case .secondaryFill, .outlined:
            return Color(red: 0.35, green: 0.39, blue: 0.45)
        }
    }

    @ViewBuilder
    private func buttonBackground(_ style: WizardButtonStyle) -> some View {
        switch style {
        case .secondaryFill:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.95, green: 0.96, blue: 0.97))
        case .outlined:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        case .primary:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MeshFluxTheme.meshBlue)
        case .disabled:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.72, green: 0.78, blue: 0.88))
        }
    }

    @ViewBuilder
    private func buttonOverlay(_ style: WizardButtonStyle) -> some View {
        switch style {
        case .outlined:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.83, green: 0.85, blue: 0.89), lineWidth: 1.5)
        default:
            EmptyView()
        }
    }

    private func sourceColors(for source: SourceItem) -> (fill: Color, border: Color, iconBackground: Color) {
        let isSelected = selectedSourceID == source.id
        switch source.status {
        case .waiting:
            return (
                Color(red: 0.97, green: 0.97, blue: 0.98),
                Color(red: 0.90, green: 0.91, blue: 0.93),
                Color(red: 0.92, green: 0.93, blue: 0.95)
            )
        case .searching:
            return (
                Color(red: 0.94, green: 0.97, blue: 1.00),
                MeshFluxTheme.meshBlue.opacity(0.55),
                MeshFluxTheme.meshBlue
            )
        case .found:
            return (
                isSelected ? Color(red: 0.94, green: 0.98, blue: 0.96) : Color(red: 0.95, green: 0.99, blue: 0.97),
                isSelected ? MeshFluxTheme.meshBlue : Color(red: 0.06, green: 0.73, blue: 0.50),
                Color(red: 0.06, green: 0.73, blue: 0.50)
            )
        case .failed:
            return (
                Color(red: 0.99, green: 0.97, blue: 0.97),
                Color(red: 0.95, green: 0.78, blue: 0.80),
                Color(red: 0.90, green: 0.91, blue: 0.93)
            )
        }
    }

    @ViewBuilder
    private func sourceIcon(for source: SourceItem) -> some View {
        switch source.status {
        case .waiting:
            Image(systemName: waitingSymbol(for: source.kind))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(red: 0.48, green: 0.52, blue: 0.58))
        case .searching:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(hasCompletedSearch ? 0 : 360))
                .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: progress)
        case .found:
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Color.red.opacity(0.82))
        }
    }

    private func waitingSymbol(for kind: SourceKind) -> String {
        switch kind {
        case .github:
            return "chevron.left.forwardslash.chevron.right"
        case .community:
            return "person.2.fill"
        case .privateNode:
            return "server.rack"
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        hasCompletedSearch = true
        installError = "已取消配置搜索。你可以导入本地配置，或稍后重试下载。"
        for index in sources.indices where sources[index].status == .searching {
            sources[index].status = .waiting
            sources[index].message = "已取消"
        }
    }

    private func startRealSearch() {
        searchTask?.cancel()
        installError = nil
        selectedSourceID = nil
        progress = 0
        isSearching = true
        hasCompletedSearch = false
        sources = sources.map { item in
            var copy = item
            copy.status = .waiting
            copy.payloadText = nil
            copy.byteCount = nil
            copy.message = "等待开始"
            copy.errorDetail = nil
            return copy
        }

        searchTask = Task {
            await searchAllSources()
        }
    }

    private func searchAllSources() async {
        let total = max(1, sources.count)
        await withTaskGroup(of: (UUID, FetchResult).self) { group in
            for (index, item) in sources.enumerated() {
                group.addTask {
                    let delaySeconds = Double(index) * 0.7
                    if delaySeconds > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    }
                    await MainActor.run {
                        if let idx = sources.firstIndex(where: { $0.id == item.id }) {
                            sources[idx].status = .searching
                            sources[idx].message = "正在下载配置内容..."
                        }
                    }
                    let result = await fetchBootstrap(from: item.endpoint)
                    return (item.id, result)
                }
            }

            var completed = 0
            for await (id, result) in group {
                completed += 1
                await MainActor.run {
                    if let idx = sources.firstIndex(where: { $0.id == id }) {
                        switch result {
                        case .success(let payload, let bytes):
                            sources[idx].status = .found
                            sources[idx].payloadText = payload
                            sources[idx].byteCount = bytes
                            sources[idx].message = "下载成功，\(formatByteCount(bytes))"
                            sources[idx].errorDetail = nil
                            if selectedSourceID == nil {
                                selectedSourceID = id
                            }
                        case .failure(let failure):
                            sources[idx].status = .failed
                            sources[idx].message = failure.brief
                            sources[idx].errorDetail = failure.detail
                        }
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        progress = Double(completed) / Double(total)
                    }
                }
            }
        }

        await MainActor.run {
            isSearching = false
            hasCompletedSearch = true
            if !hasAvailableSource {
                installError = "3 个配置来源均不可用。请检查网络后重试，或直接导入本地配置。"
            }
        }
    }

    private enum FetchResult {
        case success(payload: String, bytes: Int)
        case failure(FetchFailure)
    }

    private struct FetchFailure {
        let brief: String
        let detail: String
    }

    private func fetchBootstrap(from endpoint: String) async -> FetchResult {
        guard let url = URL(string: endpoint) else {
            return .failure(.init(brief: "地址无效", detail: "URL 格式错误"))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.init(brief: "响应无效", detail: "服务器未返回 HTTP 响应"))
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(.init(brief: "HTTP 错误", detail: "状态码 \(http.statusCode)"))
            }
            guard !data.isEmpty else {
                return .failure(.init(brief: "空响应", detail: "服务器返回了空内容"))
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .failure(.init(brief: "空文本", detail: "返回内容为空白文本"))
            }
            do {
                _ = try parseImportPayload(trimmed)
                return .success(payload: trimmed, bytes: data.count)
            } catch {
                return .failure(.init(brief: "内容格式错误", detail: "不是可安装的 JSON 配置"))
            }
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return .failure(.init(brief: "请求超时", detail: "20 秒内未收到有效响应"))
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .failure(.init(brief: "连接失败", detail: error.localizedDescription))
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return .failure(.init(brief: "TLS 错误", detail: error.localizedDescription))
            default:
                return .failure(.init(brief: "网络错误", detail: error.localizedDescription))
            }
        } catch {
            return .failure(.init(brief: "请求失败", detail: error.localizedDescription))
        }
    }

    private func installSelectedSource() {
        installError = nil
        guard let selectedSource, let payload = selectedSource.payloadText else {
            installError = "请先选择一个可用配置来源。"
            return
        }

        do {
            let (providerID, providerName, packageHash, configData, routingRulesData, ruleSetURLMap) = try parseImportPayload(payload)
            let resolvedID = providerID.isEmpty ? "bootstrap-\(selectedSource.kind)" : providerID
            let resolvedName = providerName.isEmpty ? selectedSource.name : providerName
            let pseudoProvider = TrafficProvider(
                id: resolvedID,
                name: resolvedName,
                description: "引导配置安装",
                config_url: selectedSource.endpoint,
                tags: ["Bootstrap"],
                author: "Bootstrap",
                updated_at: "",
                provider_hash: nil,
                package_hash: packageHash.isEmpty ? nil : packageHash,
                price_per_gb_usd: nil,
                detail_url: nil
            )

            onClose()
            DispatchQueue.main.async {
                ProviderInstallWindowManager.shared.show(
                    provider: pseudoProvider,
                    installAction: { selectAfterInstall, progress in
                        try await MarketService.shared.installProviderFromImportedConfig(
                            providerID: resolvedID,
                            providerName: resolvedName,
                            packageHash: packageHash,
                            configData: configData,
                            routingRulesData: routingRulesData,
                            ruleSetURLMap: ruleSetURLMap,
                            selectAfterInstall: selectAfterInstall,
                            progress: progress
                        )
                    },
                    onInstallingChange: { isInstalling in
                        if !isInstalling {
                            onInstallResolvedConfig()
                        }
                    }
                )
            }
        } catch {
            installError = error.localizedDescription
        }
    }

    private func parseImportPayload(_ text: String) throws -> (providerID: String, providerName: String, packageHash: String, configData: Data, routingRulesData: Data?, ruleSetURLMap: [String: String]?) {
        let rawData: Data
        if let b64 = Data(base64Encoded: text), !b64.isEmpty, (try? JSONSerialization.jsonObject(with: b64, options: [.fragmentsAllowed])) != nil {
            rawData = b64
        } else {
            rawData = Data(text.utf8)
        }

        let any = try JSONSerialization.jsonObject(with: rawData, options: [.fragmentsAllowed])
        if let dict = any as? [String: Any],
           let configAny = dict["config"] ?? dict["config_json"] ?? dict["configJSON"] ?? dict["singbox_config"] {
            let providerID = (dict["provider_id"] as? String) ?? (dict["providerID"] as? String) ?? ""
            let providerName = (dict["name"] as? String) ?? ""
            let packageHash = (dict["package_hash"] as? String) ?? (dict["packageHash"] as? String) ?? ""
            let configData = try normalizedJSONData(from: configAny)
            let routingAny = dict["routing_rules"] ?? dict["routing_rules_json"] ?? dict["routingRules"]
            let routingRulesData = try routingAny.map { try normalizedJSONData(from: $0) }
            let ruleSetURLMap: [String: String]?
            if let rsAny = dict["rule_set_urls"] ?? dict["ruleSetURLs"] ?? dict["rule_sets"] {
                ruleSetURLMap = try parseRuleSetURLMap(rsAny)
            } else {
                ruleSetURLMap = nil
            }
            return (providerID, providerName, packageHash, configData, routingRulesData, ruleSetURLMap)
        }

        let configData = try normalizedJSONData(from: any)
        return ("", "", "", configData, nil, nil)
    }

    private func normalizedJSONData(from any: Any) throws -> Data {
        if let string = any as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = Data(trimmed.utf8)
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return data
        }
        return try JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])
    }

    private func parseRuleSetURLMap(_ any: Any) throws -> [String: String] {
        if let dict = any as? [String: Any] {
            var result: [String: String] = [:]
            for (key, value) in dict {
                if let string = value as? String, !string.isEmpty {
                    result[key] = string
                }
            }
            return result
        }
        if let array = any as? [Any] {
            var result: [String: String] = [:]
            for item in array {
                guard let dict = item as? [String: Any] else { continue }
                guard let tag = dict["tag"] as? String, !tag.isEmpty else { continue }
                guard let url = dict["url"] as? String, !url.isEmpty else { continue }
                result[tag] = url
            }
            return result
        }
        return [:]
    }

    private func formatByteCount(_ count: Int) -> String {
        let kb = Double(count) / 1024.0
        if kb >= 1024 {
            return String(format: "%.1f MB", kb / 1024.0)
        }
        if kb >= 1 {
            return String(format: "%.1f KB", kb)
        }
        return "\(count) B"
    }
}

private struct MenuCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                MeshFluxTheme.techCardBackground(scheme: scheme)
            }
    }
}

private struct MenuHeroCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                MeshFluxTheme.techCardBackground(scheme: scheme, glowColor: MeshFluxTheme.meshBlue)
            }
    }
}

private struct MenuDashedVRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay {
                Path { p in
                    p.move(to: CGPoint(x: 0.5, y: 0))
                    p.addLine(to: CGPoint(x: 0.5, y: 9999))
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            MeshFluxTheme.meshBlue.opacity(0.55),
                            Color.white.opacity(0.30),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 3])
                )
            }
            .frame(width: 1)
            .clipped()
    }
}

private struct MiniTrafficChart: View {
    let upSeries: [Double]
    let downSeries: [Double]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxV = max(upSeries.max() ?? 0, downSeries.max() ?? 0)
            let range = max(0.0001, maxV)
            let rect = CGRect(x: 10, y: 8, width: w - 20, height: h - 16)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .light ? 0.62 : 0.10),
                                Color.white.opacity(scheme == .light ? 0.42 : 0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .light ? 0.12 : 0.10), lineWidth: 1)
                    }

                // Subtle grid hints for readability.
                ForEach(1..<3, id: \.self) { i in
                    Path { p in
                        let y = h * CGFloat(i) / 3.0
                        p.move(to: CGPoint(x: 10, y: y))
                        p.addLine(to: CGPoint(x: w - 10, y: y))
                    }
                    .stroke(Color.white.opacity(scheme == .light ? 0.08 : 0.05), lineWidth: 1)
                }

                Path { p in
                    p.move(to: CGPoint(x: rect.minX, y: rect.maxY - 0.5))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 0.5))
                }
                .stroke(Color.white.opacity(scheme == .light ? 0.18 : 0.08), lineWidth: 1)

                // Area fills
                Path { p in
                    plotValues(series: upSeries, in: rect, range: range, path: &p, close: true, h: h)
                }
                .fill(
                    LinearGradient(
                        colors: [MeshFluxTheme.meshBlue.opacity(0.3), MeshFluxTheme.meshBlue.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { p in
                    plotValues(series: downSeries, in: rect, range: range, path: &p, close: true, h: h)
                }
                .fill(
                    LinearGradient(
                        colors: [MeshFluxTheme.meshMint.opacity(0.3), MeshFluxTheme.meshMint.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { p in
                    plotValues(series: upSeries, in: rect, range: range, path: &p)
                }
                .stroke(MeshFluxTheme.meshBlue.opacity(0.95), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                .shadow(color: MeshFluxTheme.meshBlue.opacity(0.14), radius: 2, x: 0, y: 0)

                Path { p in
                    plotValues(series: downSeries, in: rect, range: range, path: &p)
                }
                .stroke(MeshFluxTheme.meshMint.opacity(0.95), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                .shadow(color: MeshFluxTheme.meshMint.opacity(0.14), radius: 2, x: 0, y: 0)
            }
        }
    }

    private func plotValues(series: [Double], in rect: CGRect, range: Double, path: inout Path, close: Bool = false, h: CGFloat = 0) {
        guard series.count >= 2 else { return }
        let stepX = rect.width / CGFloat(max(1, series.count - 1))
        
        var points: [CGPoint] = []
        for (i, v) in series.enumerated() {
            let x = rect.minX + CGFloat(i) * stepX
            let norm = max(0.0, min(1.0, v / range))
            let y = rect.minY + rect.height * (1.0 - CGFloat(norm))
            points.append(CGPoint(x: x, y: y))
        }

        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }

        if close {
            path.addLine(to: CGPoint(x: points.last!.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: points.first!.x, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

final class MenuSingleWindowPresenter: NSObject, NSWindowDelegate {
    private weak var trafficWindow: NSWindow?
    private weak var nodeWindow: NSWindow?
    private var trafficHostingView: NSHostingView<AnyView>?
    var hasDetachedWindows: Bool { trafficWindow != nil || nodeWindow != nil }

    func showTrafficMoreInfo(
        seriesUp: [Double],
        seriesDown: [Double],
        upKBps: Double,
        downKBps: Double,
        upTotalBytes: Int64,
        downTotalBytes: Int64
    ) {
        let root = trafficView(
            seriesUp: seriesUp,
            seriesDown: seriesDown,
            upKBps: upKBps,
            downKBps: downKBps,
            upTotalBytes: upTotalBytes,
            downTotalBytes: downTotalBytes
        )
        let title = "流量合计"
        let size = NSSize(width: 560, height: 420)
        if let w = trafficWindow {
            trafficHostingView?.rootView = AnyView(root)
            NSApp.activate(ignoringOtherApps: true)
            w.level = .floating
            w.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: AnyView(root))
        trafficHostingView = hosting
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hosting
        w.title = title
        w.minSize = NSSize(width: size.width, height: size.height)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        trafficWindow = w
        NotificationCenter.default.post(name: .menuDetachedWindowsChanged, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func showNodePicker(vendorName: String, store: MenuNodeStore, vpnController: VPNController) {
        let root = MenuNodePickerWindowView(store: store, vpnController: vpnController, vendorName: vendorName)
        let title = "节点"
        let size = NSSize(width: 560, height: 520)
        if let w = nodeWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.level = .floating
            w.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: AnyView(root))
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hosting
        w.title = title
        w.minSize = NSSize(width: size.width, height: size.height)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        nodeWindow = w
        NotificationCenter.default.post(name: .menuDetachedWindowsChanged, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func updateTrafficMoreInfo(
        seriesUp: [Double],
        seriesDown: [Double],
        upKBps: Double,
        downKBps: Double,
        upTotalBytes: Int64,
        downTotalBytes: Int64
    ) {
        guard trafficWindow != nil else { return }
        trafficHostingView?.rootView = AnyView(
            trafficView(
                seriesUp: seriesUp,
                seriesDown: seriesDown,
                upKBps: upKBps,
                downKBps: downKBps,
                upTotalBytes: upTotalBytes,
                downTotalBytes: downTotalBytes
            )
        )
    }

    private func trafficView(
        seriesUp: [Double],
        seriesDown: [Double],
        upKBps: Double,
        downKBps: Double,
        upTotalBytes: Int64,
        downTotalBytes: Int64
    ) -> some View {
        TrafficMoreInfoView(
            seriesUp: seriesUp,
            seriesDown: seriesDown,
            upKBps: upKBps,
            downKBps: downKBps,
            upTotalBytes: upTotalBytes,
            downTotalBytes: downTotalBytes
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if trafficWindow === closingWindow {
            trafficWindow = nil
            trafficHostingView = nil
        }
        if nodeWindow === closingWindow {
            nodeWindow = nil
        }
        NotificationCenter.default.post(name: .menuDetachedWindowsChanged, object: nil)
    }
}

private extension Notification.Name {
    static let menuDetachedWindowsChanged = Notification.Name("menuDetachedWindowsChanged")
}

private struct TrafficMoreInfoView: View {
    let seriesUp: [Double]
    let seriesDown: [Double]
    let upKBps: Double
    let downKBps: Double
    let upTotalBytes: Int64
    let downTotalBytes: Int64

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 12) {
                headerSection

                HStack(spacing: 12) {
                    MetricPill(title: "上行合计", value: OMLibboxFormatBytes(upTotalBytes), color: MeshFluxTheme.meshBlue, systemImage: "arrow.up.right")
                    MetricPill(title: "下行合计", value: OMLibboxFormatBytes(downTotalBytes), color: MeshFluxTheme.meshMint, systemImage: "arrow.down.right")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 12) {
                            trafficDeltaPill(
                                title: "上行增量",
                                value: formatKBps(upKBps),
                                tint: MeshFluxTheme.meshBlue,
                                systemImage: "arrow.up"
                            )
                            trafficDeltaPill(
                                title: "下行增量",
                                value: formatKBps(downKBps),
                                tint: MeshFluxTheme.meshMint,
                                systemImage: "arrow.down"
                            )
                        }
                        Spacer()
                        Text("连接态显示实时数据")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.82))
                    }

                    BigTrafficChart(upSeries: seriesUp, downSeries: seriesDown)
                        .frame(maxWidth: .infinity)
                        .frame(height: 208)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MeshFluxTheme.cardFill(.light))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(MeshFluxTheme.cardStroke(.light), lineWidth: 1)
                )
            }
            .padding(18)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("流量合计")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.72))
                Text("连接状态流量")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("连接期间显示上下行总量与实时波动。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        }
    }

    private func trafficDeltaPill(title: String, value: String, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.10))
        }
    }
}

private struct BigTrafficChart: View {
    let upSeries: [Double]
    let downSeries: [Double]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxV = max(upSeries.max() ?? 0, downSeries.max() ?? 0, 0.001)
            let rect = CGRect(x: 0, y: 10, width: w, height: h - 20)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.04 : 0.22),
                                Color.white.opacity(scheme == .dark ? 0.02 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Path { p in
                    let steps = 5
                    for i in 0...steps {
                        let y = rect.minY + rect.height * CGFloat(i) / CGFloat(steps)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    let xSteps = 10
                    for i in 0...xSteps {
                        let x = w * CGFloat(i) / CGFloat(xSteps)
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                }
                .stroke(MeshFluxTheme.meshBlue.opacity(scheme == .dark ? 0.08 : 0.05), lineWidth: 1)

                Path { p in
                    plotBigValues(series: upSeries, in: rect, maxV: maxV, path: &p, close: true)
                }
                .fill(
                    LinearGradient(
                        colors: [MeshFluxTheme.meshBlue.opacity(0.14), MeshFluxTheme.meshBlue.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { p in
                    plotBigValues(series: downSeries, in: rect, maxV: maxV, path: &p, close: true)
                }
                .fill(
                    LinearGradient(
                        colors: [MeshFluxTheme.meshMint.opacity(0.14), MeshFluxTheme.meshMint.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { p in
                    plotBigValues(series: upSeries, in: rect, maxV: maxV, path: &p)
                }
                .stroke(MeshFluxTheme.meshBlue, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))

                Path { p in
                    plotBigValues(series: downSeries, in: rect, maxV: maxV, path: &p)
                }
                .stroke(MeshFluxTheme.meshMint, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func plotBigValues(series: [Double], in rect: CGRect, maxV: Double, path: inout Path, close: Bool = false) {
        guard series.count >= 2 else { return }
        let stepX = rect.width / CGFloat(series.count - 1)
        
        var points: [CGPoint] = []
        for (i, v) in series.enumerated() {
            let x = rect.minX + CGFloat(i) * stepX
            let norm = v / maxV
            let y = rect.minY + rect.height * (1.0 - CGFloat(norm))
            points.append(CGPoint(x: x, y: y))
        }

        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }

        if close {
            path.addLine(to: CGPoint(x: points.last!.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: points.first!.x, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private func formatKBps(_ value: Double) -> String {
    if value >= 1024 {
        return String(format: "%.1f MB/s", value / 1024.0)
    }
    if value >= 10 {
        return String(format: "%.0f KB/s", value)
    }
    return String(format: "%.1f KB/s", value)
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Circle()
                    .strokeBorder(color.opacity(0.28), lineWidth: 1)
                    .frame(width: 34, height: 34)
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MeshFluxTheme.cardFill(.light))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(.light), lineWidth: 1)
        )
    }
}
struct ProviderTriggerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ProfileItemButtonStyle: ButtonStyle {
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isHovered || configuration.isPressed {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .onHover { isHovered = $0 }
    }
}
