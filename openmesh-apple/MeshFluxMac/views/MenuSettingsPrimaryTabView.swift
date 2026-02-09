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
    @State private var shouldShowInitButton = false
    @State private var initPendingTags: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topControlAndProfile
            Divider().opacity(0.55)
            trafficCard
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
        if let match = profileList.first(where: { $0.id == selectedProfileID }) {
            return match.name
        }
        return "官方供应商"
    }

    private var selectedMerchantName: String {
        profileList.first(where: { $0.id == selectedProfileID })?.name ?? "官方供应商"
    }

    private var topControlAndProfile: some View {
        MenuHeroCard {
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
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.95))
                        Text(displayVersion)
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary.opacity(0.9))
                        Text(connectionStatusText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(connectionStatusColor)
                    }
                }

                Spacer(minLength: 10)

                MenuDashedVRule()
                    .frame(height: 54)
                    .padding(.horizontal, 2)

                profilePickerCompact
                    .frame(maxWidth: 180, alignment: .leading)
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

    private var connectionStatusColor: Color {
        if vpnController.isConnecting { return .secondary }
        return vpnController.isConnected ? .green : .secondary
    }

    private func toggleVPNFromHeader() {
        if vpnButtonShowsStop {
            optimisticShowStop = false
        } else {
            optimisticShowStop = true
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
            Text("流量商户")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isLoadingProfiles {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("加载中…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if profileList.isEmpty {
                Text("暂无配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                            print("[Market] Update tapped provider=\(updateProviderID) local=\(updateLocalHash) remote=\(updateRemoteHash)")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .disabled(isReasserting || vpnController.isConnecting || isLoadingProfiles)
                .opacity(isReasserting || vpnController.isConnecting || isLoadingProfiles ? 0.65 : 1.0)
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
        Menu {
            ForEach(profileList) { p in
                Button {
                    selectedProfileID = p.id
                    isReasserting = true
                    Task { await onSwitchProfile(p.id) }
                } label: {
                    if p.id == selectedProfileID {
                        Label(p.name, systemImage: "checkmark")
                    } else {
                        Text(p.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedMerchantName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(MeshFluxTheme.meshBlue.opacity(0.22), lineWidth: 1)
            }
        }
        .menuStyle(.button)
    }

    private var trafficCard: some View {
        MenuCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Button("More info") {
                        windowPresenter.showTrafficMoreInfo(
                            seriesUp: uplinkKBpsSeries,
                            seriesDown: downlinkKBpsSeries,
                            upKBps: uplinkKBps,
                            downKBps: downlinkKBps,
                            upTotalBytes: uplinkTotalBytes,
                            downTotalBytes: downlinkTotalBytes
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                            }
                    }
                }

                trafficLegend

                MiniTrafficChart(upSeries: uplinkKBpsSeries, downSeries: downlinkKBpsSeries)
                    .frame(height: 52)

                Divider().opacity(0.35)

                nodeTrafficPanel
                    .padding(.top, 10)
            }
        }
    }

    private var nodeTrafficPanel: some View {
        VStack(spacing: 0) {
            nodeTrafficRowContent
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var nodeTrafficRowContent: some View {
        let node = nodeStore.selectedNode
        let nodeName = node?.name ?? (nodeStore.selectedNodeID.isEmpty ? "—" : nodeStore.selectedNodeID)
        let nodeAddress = node?.address ?? "—"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(nodeName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(nodeAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(Color.blue)
                    Text(formatKBps(uplinkKBps))
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(Color.green)
                    Text(formatKBps(downlinkKBps))
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 8)
                if vpnController.isConnected {
                    Button {
                        windowPresenter.showNodePicker(vendorName: vendorName, store: nodeStore, vpnController: vpnController)
                    } label: {
                        MeshFluxTintButton(title: "切换", systemImage: "bolt.fill", tint: .orange, isBusy: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                openExternalURL("https://github.com/MeshNetProtocol/openmesh-cli")
            } label: {
                Image(systemName: "pills.fill")
            }
            .buttonStyle(.plain)
            .help("Source Code")

            Button {
                openExternalURL("https://meshnetprotocol.github.io/")
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .help("About MeshNet Protocol")

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.plain)
            .help("退出")
        }
        .padding(.top, 2)
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
        HStack(spacing: 14) {
            legendItem(color: .blue, title: "上行合计", value: OMLibboxFormatBytes(uplinkTotalBytes))
            legendItem(color: .green, title: "下行合计", value: OMLibboxFormatBytes(downlinkTotalBytes))
            Spacer()
        }
    }

    private func legendItem(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(value)")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.9))
                .lineLimit(1)
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

private struct MenuCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MeshFluxTheme.cardFill(scheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MeshFluxTheme.cardFill(scheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .fill(Color.white.opacity(scheme == .light ? 0.55 : 0.08))
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
                    .stroke(Color.white.opacity(scheme == .light ? 0.10 : 0.08), lineWidth: 1)
                }

                Path { p in
                    plotValues(series: upSeries, in: rect, range: range, path: &p)
                }
                .stroke(MeshFluxTheme.meshBlue.opacity(0.95), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                Path { p in
                    plotValues(series: downSeries, in: rect, range: range, path: &p)
                }
                .stroke(MeshFluxTheme.meshMint.opacity(0.95), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func plotValues(series: [Double], in rect: CGRect, range: Double, path: inout Path) {
        guard series.count >= 2 else { return }
        let stepX = rect.width / CGFloat(max(1, series.count - 1))
        for (i, v) in series.enumerated() {
            let x = CGFloat(i) * stepX
            let norm = max(0.0, min(1.0, v / range))
            let y = rect.height * (1.0 - CGFloat(norm))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
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

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("流量合计")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("连接态显示实时数据")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.9))
                }

                HStack(spacing: 12) {
                    MetricPill(title: "上行合计", value: OMLibboxFormatBytes(upTotalBytes), color: MeshFluxTheme.meshBlue)
                    MetricPill(title: "下行合计", value: OMLibboxFormatBytes(downTotalBytes), color: MeshFluxTheme.meshMint)
                }

                MeshFluxCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Label("上行增量", systemImage: "arrow.up")
                                .foregroundStyle(MeshFluxTheme.meshBlue)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(formatKBps(upKBps))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.92))
                            Label("下行增量", systemImage: "arrow.down")
                                .foregroundStyle(MeshFluxTheme.meshMint)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(formatKBps(downKBps))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.92))
                            Spacer()
                        }
                        MiniTrafficChart(upSeries: seriesUp, downSeries: seriesDown)
                            .frame(height: 220)
                    }
                    .padding(14)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
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

}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        MeshFluxCard(cornerRadius: 999) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color.opacity(0.95))
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.9))
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.95))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }
}
