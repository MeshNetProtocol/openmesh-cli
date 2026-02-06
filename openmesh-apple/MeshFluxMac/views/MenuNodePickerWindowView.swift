import SwiftUI
import AppKit
import Combine
import Network
import VPNLibrary

final class MenuNodeStore: ObservableObject {
    @Published var nodes: [MenuNodeCandidate]
    @Published var selectedNodeID: String

    @Published var isTestingAll = false
    @Published var testingNodeID: String?
    @Published var isApplyingSelection = false
    @Published var errorMessage: String?
    @Published var canSelectNodes = true

    private var onTestAllLive: (() async throws -> Void)?
    private var onTestOneLive: ((String) async throws -> Void)?
    private var onSelectLive: ((String) async throws -> Void)?
    private var onSelectOffline: ((String) -> Void)?
    private var onURLTest: (() async throws -> [String: Int])?

    private enum PendingTestKind: Equatable {
        case all
        case one(String)
    }

    private struct PendingTest {
        let token: UUID
        let kind: PendingTestKind
        let startedAt: Date
        let snapshotLatencyByID: [String: Int?]
    }

    // Live urlTest() usually returns immediately (it just triggers the test in the extension),
    // while results arrive later via group updates. Hold "testing" UI state until we observe
    // updated latency values (or time out).
    private var pendingTest: PendingTest?

    init(
        nodes: [MenuNodeCandidate] = [
            .init(id: "hk-1", name: "香港节点", address: "1.1.1.1", port: nil, region: "Hong Kong", latencyMs: 46),
            .init(id: "jp-1", name: "日本节点", address: "8.8.8.8", port: nil, region: "Japan", latencyMs: 78),
            .init(id: "sg-1", name: "新加坡节点", address: "9.9.9.9", port: nil, region: "Singapore", latencyMs: 63),
            .init(id: "us-1", name: "美国节点", address: "4.4.4.4", port: nil, region: "United States", latencyMs: 132),
        ],
        selectedNodeID: String = "hk-1"
    ) {
        self.nodes = nodes
        self.selectedNodeID = selectedNodeID
    }

    var selectedNode: MenuNodeCandidate? {
        nodes.first(where: { $0.id == selectedNodeID })
    }

    func applyLiveGroup(
        _ group: OutboundGroupModel,
        nodeMetadataByTag: [String: MenuNodeCandidate] = [:],
        canSelect: Bool,
        onTestAll: @escaping () async throws -> Void,
        onTestOne: @escaping (String) async throws -> Void,
        onSelect: @escaping (String) async throws -> Void
    ) {
        let mapped = group.items.map { item in
            let metadata = nodeMetadataByTag[item.tag]
            return MenuNodeCandidate(
                id: item.tag,
                name: metadata?.name ?? item.tag,
                address: metadata?.address ?? "—",
                port: metadata?.port,
                region: metadata?.region ?? Self.regionFromTag(item.tag),
                latencyMs: item.urlTestDelay > 0 ? Int(item.urlTestDelay) : nil
            )
        }
        nodes = mapped
        canSelectNodes = canSelect
        if mapped.contains(where: { $0.id == group.selected }) {
            selectedNodeID = group.selected
        } else if let first = mapped.first {
            selectedNodeID = first.id
        } else {
            selectedNodeID = ""
        }
        onTestAllLive = onTestAll
        onTestOneLive = onTestOne
        if canSelect {
            onSelectLive = onSelect
        } else {
            onSelectLive = nil
        }
        onSelectOffline = nil

        // If a urlTest request is in-flight, clear the UI "testing" state once we observe
        // updated delays coming back from the extension (with a small minimum hold so the
        // user can actually see the feedback).
        maybeResolvePendingTest(with: mapped)
    }

    func setOfflineNodes(_ nodes: [MenuNodeCandidate], selectedNodeID: String?, onSelectOffline: ((String) -> Void)? = nil) {
        onTestAllLive = nil
        onTestOneLive = nil
        onSelectLive = nil
        self.onSelectOffline = onSelectOffline
        self.nodes = nodes
        canSelectNodes = true
        if let selectedNodeID, nodes.contains(where: { $0.id == selectedNodeID }) {
            self.selectedNodeID = selectedNodeID
        } else {
            self.selectedNodeID = nodes.first?.id ?? ""
        }
    }

    func setURLTestProvider(onURLTest: (() async throws -> [String: Int])?) {
        self.onURLTest = onURLTest
    }

    func clearLiveBindings() {
        onTestAllLive = nil
        onTestOneLive = nil
        onSelectLive = nil
        onSelectOffline = nil
        onURLTest = nil
        nodes = []
        selectedNodeID = ""
        canSelectNodes = false
    }

    private func snapshotLatencies() -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.latencyMs) })
    }

    private func beginPendingTest(kind: PendingTestKind, timeoutNanoseconds: UInt64 = 15_000_000_000) {
        let token = UUID()
        pendingTest = PendingTest(
            token: token,
            kind: kind,
            startedAt: Date(),
            snapshotLatencyByID: snapshotLatencies()
        )

        // Safety valve: don't keep the UI stuck if we never get group updates.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            await MainActor.run {
                guard let self else { return }
                guard self.pendingTest?.token == token else { return }
                self.pendingTest = nil
                self.isTestingAll = false
                self.testingNodeID = nil
            }
        }
    }

    private func maybeResolvePendingTest(with mapped: [MenuNodeCandidate]) {
        guard let pending = pendingTest else { return }

        func latency(for id: String) -> Int? {
            mapped.first(where: { $0.id == id })?.latencyMs
        }

        let changed: Bool = {
            switch pending.kind {
            case .all:
                // Any updated delay counts as progress.
                return mapped.contains { node in
                    pending.snapshotLatencyByID[node.id] != node.latencyMs && node.latencyMs != nil
                }
            case .one(let id):
                // Live "test one" still triggers a group urlTest; the clicked node may end up with
                // the same delay value, so treat any delay update as completion feedback.
                let before = pending.snapshotLatencyByID[id] ?? nil
                let after = latency(for: id)
                if before != after && after != nil { return true }
                return mapped.contains { node in
                    pending.snapshotLatencyByID[node.id] != node.latencyMs && node.latencyMs != nil
                }
            }
        }()

        guard changed else { return }

        let minHold: TimeInterval = 0.9
        let elapsed = Date().timeIntervalSince(pending.startedAt)
        let remaining = max(0, minHold - elapsed)
        let token = pending.token

        Task { [weak self] in
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            await MainActor.run {
                guard let self else { return }
                guard self.pendingTest?.token == token else { return }
                self.pendingTest = nil
                self.isTestingAll = false
                self.testingNodeID = nil
            }
        }
    }

    @MainActor
    func testAll() async {
        guard !isTestingAll, testingNodeID == nil else { return }
        isTestingAll = true
        testingNodeID = nil
        if let onTestAllLive {
            beginPendingTest(kind: .all)
            do {
                try await onTestAllLive()
            } catch {
                errorMessage = error.localizedDescription
                pendingTest = nil
                isTestingAll = false
            }
            return
        }
        if let onURLTest {
            do {
                let delays = try await onURLTest()
                nodes = nodes.map { n in
                    var copy = n
                    if let d = delays[n.id], d > 0 {
                        copy.latencyMs = d
                    } else {
                        copy.latencyMs = nil
                    }
                    return copy
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isTestingAll = false
            return
        }
        // Offline mode: direct TCP RTT estimation (not via VPN tunnel).
        let snapshot = nodes
        await withTaskGroup(of: (String, Int?).self) { group in
            for node in snapshot {
                group.addTask {
                    let host = node.address
                    let port = node.port ?? 443
                    let ms = await Self.tcpRTTMillis(host: host, port: port, timeoutMillis: 1500)
                    return (node.id, ms)
                }
            }
            for await (id, ms) in group {
                await MainActor.run {
                    self.nodes = self.nodes.map { n in
                        guard n.id == id else { return n }
                        var copy = n
                        copy.latencyMs = ms
                        return copy
                    }
                }
            }
        }
        isTestingAll = false
    }

    @MainActor
    func testOne(_ id: String) async {
        guard !isTestingAll, testingNodeID == nil else { return }
        testingNodeID = id
        if let onTestOneLive {
            beginPendingTest(kind: .one(id))
            do {
                try await onTestOneLive(id)
            } catch {
                errorMessage = error.localizedDescription
                pendingTest = nil
                testingNodeID = nil
            }
            return
        }
        if let onURLTest {
            do {
                let delays = try await onURLTest()
                nodes = nodes.map { n in
                    var copy = n
                    if let d = delays[n.id], d > 0 {
                        copy.latencyMs = d
                    } else {
                        copy.latencyMs = nil
                    }
                    return copy
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            testingNodeID = nil
            return
        }
        if let node = nodes.first(where: { $0.id == id }) {
            let host = node.address
            let port = node.port ?? 443
            let ms = await Self.tcpRTTMillis(host: host, port: port, timeoutMillis: 1500)
            nodes = nodes.map { n in
                guard n.id == id else { return n }
                var copy = n
                copy.latencyMs = ms
                return copy
            }
        }
        testingNodeID = nil
    }

    @MainActor
    func selectNode(_ id: String) async {
        guard selectedNodeID != id, !isApplyingSelection else { return }
        guard canSelectNodes else { return }
        if let onSelectLive {
            isApplyingSelection = true
            defer { isApplyingSelection = false }
            do {
                try await onSelectLive(id)
                selectedNodeID = id
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        selectedNodeID = id
        onSelectOffline?(id)
    }

    private static func tcpRTTMillis(host: String, port: Int, timeoutMillis: Int) async -> Int? {
        guard !host.isEmpty else { return nil }
        guard (1...65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        let start = DispatchTime.now().uptimeNanoseconds
        let queue = DispatchQueue(label: "meshflux.latency.\(UUID().uuidString)")
        let nwHost = NWEndpoint.Host(host)
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        return await withCheckedContinuation { cont in
            final class FinishFlag: @unchecked Sendable {
                private let lock = NSLock()
                private var done = false

                func testAndSet() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if done { return true }
                    done = true
                    return false
                }
            }

            let flag = FinishFlag()
            @Sendable func finish(_ value: Int?) {
                if flag.testAndSet() { return }
                conn.cancel()
                cont.resume(returning: value)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let end = DispatchTime.now().uptimeNanoseconds
                    let ms = Int((end - start) / 1_000_000)
                    finish(max(1, ms))
                case .failed:
                    finish(nil)
                default:
                    break
                }
            }

            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMillis)) {
                finish(nil)
            }
        }
    }

    private static func regionFromTag(_ tag: String) -> String {
        let normalized = tag.lowercased()
        if normalized.contains("hk") || normalized.contains("hong") { return "Hong Kong" }
        if normalized.contains("jp") || normalized.contains("japan") { return "Japan" }
        if normalized.contains("sg") || normalized.contains("singapore") { return "Singapore" }
        if normalized.contains("us") || normalized.contains("america") || normalized.contains("united") { return "United States" }
        return "Unknown"
    }
}

struct MenuNodeCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let port: Int?
    let region: String
    var latencyMs: Int?

    var latencyText: String {
        guard let latencyMs else { return "-" }
        return "\(latencyMs) ms"
    }

    var latencyColor: Color {
        guard let latencyMs else { return .secondary }
        switch latencyMs {
        case ...500: return .green
        case ...1000: return MeshFluxTheme.meshAmber
        default: return .red
        }
    }
}

struct MenuNodePickerWindowView: View {
    @ObservedObject var store: MenuNodeStore
    @ObservedObject var vpnController: VPNController
    let vendorName: String
    @State private var showAlert = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 14) {
                if !vpnController.isConnected {
                    MeshFluxCard(cornerRadius: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MeshFluxTheme.meshAmber)
                            Text("当前未连接 VPN：可以查看节点，但测速/切换会提示先连接。")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.9))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("节点")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("供应商：\(vendorName)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.9))
                    }
                    Spacer()
                    Button {
                        if requireConnected(action: "测速") {
                            Task { await store.testAll() }
                        }
                    } label: {
                        MeshFluxTintButton(
                            title: store.isTestingAll ? "测速中…" : "测速",
                            systemImage: "bolt.fill",
                            tint: .orange,
                            isBusy: store.isTestingAll
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isTestingAll || store.testingNodeID != nil || store.nodes.isEmpty)
                    .help("触发节点测速；未连接时将提示先连接 VPN")
                }

                if store.nodes.isEmpty {
                    MeshFluxCard(cornerRadius: 16) {
                        Text("暂无节点。请先选择供应商配置。")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.nodes) { node in
                                nodeRow(node)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
        .onChange(of: store.errorMessage) { message in
            showAlert = (message != nil)
        }
        .alert("节点操作失败", isPresented: $showAlert) {
            Button("确定", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func nodeRow(_ node: MenuNodeCandidate) -> some View {
        let selected = (store.selectedNodeID == node.id)
        let isTestingThisRow = store.isTestingAll || store.testingNodeID == node.id
        return MeshFluxCard(cornerRadius: 18) {
            HStack(spacing: 12) {
            Button {
                if requireConnected(action: "切换节点") {
                    Task { await store.selectNode(node.id) }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            selected
                                ? MeshFluxTheme.meshBlue.opacity(scheme == .light ? 0.18 : 0.16)
                                : Color.white.opacity(scheme == .light ? 0.30 : 0.10)
                        )
                        .frame(width: 22, height: 22)
                    Circle()
                        .strokeBorder(
                            selected
                                ? MeshFluxTheme.meshBlue.opacity(0.95)
                                : MeshFluxTheme.meshCyan.opacity(scheme == .light ? 0.55 : 0.30),
                            lineWidth: 1.6
                        )
                        .frame(width: 22, height: 22)
                    if !selected {
                        // Hint the "radio" affordance so unselected rows still look clickable.
                        Circle()
                            .fill(MeshFluxTheme.meshCyan.opacity(scheme == .light ? 0.20 : 0.14))
                            .frame(width: 6, height: 6)
                    }
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(MeshFluxTheme.meshBlue)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isApplyingSelection || !store.canSelectNodes)
            .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(node.address)
                    Text("地区: \(node.region)")
                }
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(isTestingThisRow ? "测速中…" : node.latencyText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(isTestingThisRow ? .secondary : node.latencyColor)
                .frame(width: 86, alignment: .trailing)

            Button {
                if requireConnected(action: "测速") {
                    Task { await store.testOne(node.id) }
                }
            } label: {
                MeshFluxTintButton(
                    title: store.testingNodeID == node.id ? "测速中…" : "测速",
                    systemImage: "bolt.fill",
                    tint: .orange,
                    isBusy: store.testingNodeID == node.id
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isTestingAll || store.testingNodeID != nil || store.isApplyingSelection)
            .help("触发节点测速；未连接时将提示先连接 VPN")

            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
    }

    @MainActor
    private func requireConnected(action: String) -> Bool {
        guard vpnController.isConnected else {
            store.errorMessage = "请先连接 VPN 后再\(action)。"
            showAlert = true
            return false
        }
        return true
    }
}
