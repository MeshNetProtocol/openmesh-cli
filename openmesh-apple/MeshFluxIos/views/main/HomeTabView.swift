import Foundation
import SwiftUI
import NetworkExtension
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
    let libbox = OMLibboxVersion()
    if !libbox.isEmpty, libbox.lowercased() != "unknown" {
        return libbox
    }
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    if !short.isEmpty { return build.isEmpty ? short : "\(short) (\(build))" }
    return "—"
}

struct HomeTabView: View {
    @EnvironmentObject private var vpnController: VPNController

    @StateObject private var statusClient = StatusCommandClient()
    @StateObject private var groupClient = GroupCommandClient()

    @State private var profileList: [Profile] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var profileLoadError: String?

    @State private var showOutboundPicker = false
    @State private var urlTesting = false

    private var vpnStatus: String { vpnStatusText(vpnController.status) }
    private var isConnecting: Bool { vpnController.isConnecting }
    private var appVersion: String { prettyVersionString() }

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

    private var trafficSummaryText: String {
        guard let msg = statusClient.status, msg.trafficAvailable else { return "—" }
        return "上行合计 \(OMLibboxFormatBytes(msg.uplinkTotal))  ·  下行合计 \(OMLibboxFormatBytes(msg.downlinkTotal))"
    }

    private var trafficSpeedText: String {
        guard let msg = statusClient.status, msg.trafficAvailable else { return "—" }
        return "↑ \(OMLibboxFormatBytes(msg.uplink))/s   ↓ \(OMLibboxFormatBytes(msg.downlink))/s"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.95, blue: 1.0),
                    Color(uiColor: .systemGroupedBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    trafficCard
                    outboundCard
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showOutboundPicker) {
            NavigationView {
                OutboundPickerSheet(
                    groupClient: groupClient,
                    group: currentGroup
                )
            }
        }
        .onAppear {
            Task { await vpnController.load() }
            Task { await loadProfiles() }
            updateCommandClients(connected: vpnController.isConnected)
        }
        .onChange(of: vpnController.isConnected) { connected in
            updateCommandClients(connected: connected)
        }
    }

    private var headerCard: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("MeshFlux")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                        Text(appVersion)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        StatusDot(isActive: vpnController.isConnected)
                        Text(vpnStatus)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(vpnController.isConnected ? .green : .secondary)
                    }

                    if profileList.isEmpty {
                        Text(profileLoadError == nil ? "正在加载流量商户…" : "加载失败：\(profileLoadError ?? "")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 10) {
                            Text("流量商户")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $selectedProfileID) {
                                ForEach(profileList, id: \.mustID) { p in
                                    Text(p.name).tag(p.mustID)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .onChange(of: selectedProfileID) { newId in
                                Task { await switchProfile(newId) }
                            }

                            Spacer()
                        }
                    }
                }

                Spacer()

                Button {
                    vpnController.toggleVPN()
                } label: {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView().scaleEffect(0.9)
                        }
                        Text(vpnController.isConnected ? "断开" : "连接")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(vpnController.isConnected ? Color.red : Color.blue)
                    )
                }
                .disabled(isConnecting)
            }
        }
    }

    private var trafficCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("流量")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(trafficSummaryText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                TrafficBar(
                    isActive: vpnController.isConnected
                )

                HStack {
                    Text(trafficSpeedText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
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
                    Spacer()
                    if let delay = currentOutboundDelayText {
                        Text(delay)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(currentOutboundDisplay)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
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

    private func updateCommandClients(connected: Bool) {
        if connected {
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
            var list = try await ProfileManager.list()
            if list.isEmpty {
                await DefaultProfileHelper.ensureDefaultProfileIfNeeded()
                list = try await ProfileManager.list()
            }

            var sid = await SharedPreferences.selectedProfileID.get()
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
                    .fill(Color(uiColor: .systemBackground))
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
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

private struct TrafficBar: View {
    let isActive: Bool

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.blue.opacity(isActive ? 0.85 : 0.25))
                .frame(height: 4)
            Capsule()
                .fill(Color.green.opacity(isActive ? 0.85 : 0.25))
                .frame(height: 4)
        }
        .padding(.vertical, 6)
    }
}

private struct OutboundPickerSheet: View {
    @EnvironmentObject private var vpnController: VPNController
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var groupClient: GroupCommandClient
    let group: OutboundGroupModel?

    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var urlTesting = false

    var body: some View {
        List {
            Section {
                Text(groupTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let g = group {
                Section("节点") {
                    ForEach(g.items) { item in
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
                }
            } else {
                Section {
                    Text(vpnController.isConnected ? "暂无可用节点" : "请先连接 VPN")
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                .disabled(urlTesting || !vpnController.isConnected || group == nil)
            }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var groupTitle: String {
        guard let g = group else { return "—" }
        return "组：\(g.tag)（\(g.type)）"
    }

    private func doURLTest() async {
        guard let g = group else { return }
        urlTesting = true
        defer { urlTesting = false }
        do {
            try await groupClient.urlTest(groupTag: g.tag)
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
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
