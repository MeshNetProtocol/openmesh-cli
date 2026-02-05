import SwiftUI
import AppKit
import Combine

final class MenuNodeStore: ObservableObject {
    @Published var nodes: [MenuNodeCandidate]
    @Published var selectedNodeID: String

    @Published var isTestingAll = false
    @Published var testingNodeID: String?
    @Published var isApplyingSelection = false
    @Published var errorMessage: String?

    private var onTestAllLive: (() async throws -> Void)?
    private var onTestOneLive: ((String) async throws -> Void)?
    private var onSelectLive: ((String) async throws -> Void)?

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
            .init(id: "hk-1", name: "香港节点", address: "1.1.1.1", region: "Hong Kong", latencyMs: 46),
            .init(id: "jp-1", name: "日本节点", address: "8.8.8.8", region: "Japan", latencyMs: 78),
            .init(id: "sg-1", name: "新加坡节点", address: "9.9.9.9", region: "Singapore", latencyMs: 63),
            .init(id: "us-1", name: "美国节点", address: "4.4.4.4", region: "United States", latencyMs: 132),
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
                region: metadata?.region ?? Self.regionFromTag(item.tag),
                latencyMs: item.urlTestDelay > 0 ? Int(item.urlTestDelay) : nil
            )
        }
        nodes = mapped
        if mapped.contains(where: { $0.id == group.selected }) {
            selectedNodeID = group.selected
        } else if let first = mapped.first {
            selectedNodeID = first.id
        } else {
            selectedNodeID = ""
        }
        onTestAllLive = onTestAll
        onTestOneLive = onTestOne
        onSelectLive = onSelect

        // If a urlTest request is in-flight, clear the UI "testing" state once we observe
        // updated delays coming back from the extension (with a small minimum hold so the
        // user can actually see the feedback).
        maybeResolvePendingTest(with: mapped)
    }

    func setOfflineNodes(_ nodes: [MenuNodeCandidate], selectedNodeID: String?) {
        onTestAllLive = nil
        onTestOneLive = nil
        onSelectLive = nil
        self.nodes = nodes
        if let selectedNodeID, nodes.contains(where: { $0.id == selectedNodeID }) {
            self.selectedNodeID = selectedNodeID
        } else {
            self.selectedNodeID = nodes.first?.id ?? ""
        }
    }

    func clearLiveBindings() {
        onTestAllLive = nil
        onTestOneLive = nil
        onSelectLive = nil
        nodes = []
        selectedNodeID = ""
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
        try? await Task.sleep(nanoseconds: 450_000_000)
        nodes = nodes.map { node in
            var copy = node
            let base = copy.latencyMs ?? 80
            let jitter = Int.random(in: -15...24)
            copy.latencyMs = max(1, base + jitter)
            return copy
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
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
        try? await Task.sleep(nanoseconds: 350_000_000)
        nodes = nodes.map { node in
            guard node.id == id else { return node }
            var copy = node
            let base = copy.latencyMs ?? 80
            let jitter = Int.random(in: -12...18)
            copy.latencyMs = max(1, base + jitter)
            return copy
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        testingNodeID = nil
    }

    @MainActor
    func selectNode(_ id: String) async {
        guard selectedNodeID != id, !isApplyingSelection else { return }
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
    let region: String
    var latencyMs: Int?

    var latencyText: String {
        guard let latencyMs else { return "—" }
        return "\(latencyMs) ms"
    }

    var latencyColor: Color {
        guard let latencyMs else { return .secondary }
        switch latencyMs {
        case ..<250: return .green
        case ..<500: return .orange
        default: return .red
        }
    }
}

struct MenuNodePickerWindowView: View {
    @ObservedObject var store: MenuNodeStore
    let vendorName: String
    @State private var showAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("供应商-\(vendorName)")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await store.testAll() }
                } label: {
                    if store.isTestingAll {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text("测速中…")
                        }
                    } else {
                        Label("测速", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.orange)
                .disabled(store.isTestingAll || store.testingNodeID != nil || store.nodes.isEmpty)
                .help("触发节点测速；结果可能延迟几秒显示")
            }

            if store.nodes.isEmpty {
                Text("暂无节点。请先选择供应商配置。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.nodes) { node in
                        nodeRow(node)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
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
        return HStack(spacing: 12) {
            Button {
                Task { await store.selectNode(node.id) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? .accent : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(store.isApplyingSelection)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(node.address)
                    Text("地区: \(node.region)")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(isTestingThisRow ? "测速中…" : node.latencyText)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(isTestingThisRow ? .secondary : node.latencyColor)
                .frame(width: 86, alignment: .trailing)

            Button {
                Task { await store.testOne(node.id) }
            } label: {
                if store.testingNodeID == node.id {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("测速中…")
                    }
                } else {
                    Label("测速", systemImage: "bolt.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.orange)
            .disabled(store.isTestingAll || store.testingNodeID != nil || store.isApplyingSelection)
            .help("触发节点测速；结果可能延迟几秒显示")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }
}
