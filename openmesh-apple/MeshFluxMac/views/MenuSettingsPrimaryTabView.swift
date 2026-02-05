import SwiftUI
import AppKit
import VPNLibrary
#if os(macOS)
import ServiceManagement
#endif

struct MenuSettingsPrimaryTabView: View {
    @ObservedObject var vpnController: VPNController

    let displayVersion: String

    let isLoadingProfiles: Bool
    let profileList: [ProfilePreview]
    @Binding var selectedProfileID: Int64
    @Binding var isReasserting: Bool
    let onShowDebugSettings: () -> Void

    let onLoadProfiles: () async -> Void
    let onSwitchProfile: (Int64) async -> Void

    @State private var windowPresenter = MenuSingleWindowPresenter()
    @StateObject private var nodeStore = MenuNodeStore()
    @State private var startAtLogin = false

    @State private var uplinkKBps: Double = 3.0
    @State private var downlinkKBps: Double = 5.5
    @State private var leftGB: Double = 111
    @State private var totalGB: Double = 500
    @State private var seriesUp: [Double] = Array(repeating: 2.0, count: 36)
    @State private var seriesDown: [Double] = Array(repeating: 4.0, count: 36)
    @State private var optimisticShowStop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topControlAndProfile
            Divider().opacity(0.55)
            trafficCard
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.top, 4)
        .task {
            if isLoadingProfiles {
                await onLoadProfiles()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    tickFakeTraffic()
                }
            }
        }
        .onChange(of: vpnController.isConnecting) { _ in
            clearOptimisticStateIfNeeded()
        }
        .onChange(of: vpnController.isConnected) { _ in
            clearOptimisticStateIfNeeded()
        }
        .task {
            #if os(macOS)
            startAtLogin = (SMAppService.mainApp.status == .enabled)
            #endif
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(displayVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(connectionStatusText)
                            .font(.subheadline)
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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
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
                merchantMenuButton
                    .disabled(isReasserting || vpnController.isConnecting || isLoadingProfiles)
                    .opacity(isReasserting || vpnController.isConnecting || isLoadingProfiles ? 0.65 : 1.0)
            }
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
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
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
                            leftGB: leftGB,
                            totalGB: totalGB,
                            seriesUp: seriesUp,
                            seriesDown: seriesDown
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                MiniTrafficChart(upSeries: seriesUp, downSeries: seriesDown)
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
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 1)
        }
    }

    private var nodeTrafficRowContent: some View {
        let nodeName = nodeStore.selectedNode?.name ?? "—"
        return HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)

            Text(nodeName)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(Color.blue)
                    Text("\(formatKBps(uplinkKBps))")
                        .font(.system(.subheadline, design: .monospaced))
                }
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(Color.green)
                    Text("\(formatKBps(downlinkKBps))")
                        .font(.system(.subheadline, design: .monospaced))
                }
            }

            Button {
                windowPresenter.showNodePicker(vendorName: vendorName, store: nodeStore)
            } label: {
                Label("切换", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.orange)
        }
    }

    private var bottomBar: some View {
        HStack {
            Menu {
                Button("Update") {
                    NSLog("MeshFluxMac menu: Update clicked (TODO)")
                }
                Divider()
                Button("About MeshNet Protocol") {
                    openExternalURL("https://meshnetprotocol.github.io/")
                }
                Button("Source Code") {
                    openExternalURL("https://github.com/MeshNetProtocol/openmesh-cli")
                }
                Divider()
                Button {
                    toggleStartAtLogin()
                } label: {
                    if startAtLogin {
                        Label("Start at login", systemImage: "checkmark")
                    } else {
                        Text("Start at login")
                    }
                }
                Divider()
                Button("Preferences") {
                    onShowDebugSettings()
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("设置")

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

    private func toggleStartAtLogin() {
        #if os(macOS)
        do {
            if startAtLogin {
                try SMAppService.mainApp.unregister()
                startAtLogin = false
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
                startAtLogin = true
            }
        } catch {
            NSLog("MeshFluxMac StartAtLogin toggle failed: %@", error.localizedDescription)
        }
        #endif
    }

    private func tickFakeTraffic() {
        uplinkKBps = max(0.2, uplinkKBps + Double.random(in: -0.6...0.8))
        downlinkKBps = max(0.2, downlinkKBps + Double.random(in: -0.8...1.2))

        seriesUp.append(uplinkKBps)
        seriesDown.append(downlinkKBps)
        if seriesUp.count > 48 { seriesUp.removeFirst(seriesUp.count - 48) }
        if seriesDown.count > 48 { seriesDown.removeFirst(seriesDown.count - 48) }
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

    private func formatGB(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f GB", value)
        }
        return String(format: "%.1f GB", value)
    }
}

private struct MenuCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
            }
    }
}

private struct MenuHeroCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
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
                    Color(nsColor: .separatorColor).opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4])
                )
            }
            .frame(width: 1)
            .clipped()
    }
}

private struct MiniTrafficChart: View {
    let upSeries: [Double]
    let downSeries: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let all = (upSeries + downSeries)
            let minV = all.min() ?? 0
            let maxV = all.max() ?? 1
            let range = max(0.0001, maxV - minV)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))

                Path { p in
                    plot(series: upSeries, in: CGRect(x: 0, y: 0, width: w, height: h), minV: minV, range: range, path: &p)
                }
                .stroke(Color.blue.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { p in
                    plot(series: downSeries, in: CGRect(x: 0, y: 0, width: w, height: h), minV: minV, range: range, path: &p)
                }
                .stroke(Color.green.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func plot(series: [Double], in rect: CGRect, minV: Double, range: Double, path: inout Path) {
        guard series.count >= 2 else { return }
        let stepX = rect.width / CGFloat(max(1, series.count - 1))
        for (i, v) in series.enumerated() {
            let x = CGFloat(i) * stepX
            let norm = (v - minV) / range
            let y = rect.height * (1.0 - CGFloat(norm))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
    }
}

final class MenuSingleWindowPresenter: NSObject, NSWindowDelegate {
    private weak var trafficWindow: NSWindow?
    private weak var nodeWindow: NSWindow?

    func showTrafficMoreInfo(leftGB: Double, totalGB: Double, seriesUp: [Double], seriesDown: [Double]) {
        let root = TrafficMoreInfoView(leftGB: leftGB, totalGB: totalGB, seriesUp: seriesUp, seriesDown: seriesDown)
        let title = "流量合计"
        let size = NSSize(width: 560, height: 420)
        if let w = trafficWindow {
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
        trafficWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func showNodePicker(vendorName: String, store: MenuNodeStore) {
        let root = MenuNodePickerWindowView(store: store, vendorName: vendorName)
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
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

private struct TrafficMoreInfoView: View {
    let leftGB: Double
    let totalGB: Double
    let seriesUp: [Double]
    let seriesDown: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("流量合计")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("UI-only / 假数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Left \(formatGB(leftGB)) / Total \(formatGB(totalGB))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MiniTrafficChart(upSeries: seriesUp, downSeries: seriesDown)
                .frame(height: 180)

            HStack(spacing: 18) {
                MetricPill(title: "上行", value: "\(formatKBps(seriesUp.last ?? 0))", color: .blue)
                MetricPill(title: "下行", value: "\(formatKBps(seriesDown.last ?? 0))", color: .green)
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func formatGB(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f GB", value)
        }
        return String(format: "%.1f GB", value)
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
    }
}
