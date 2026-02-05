import SwiftUI
import AppKit
import Combine

final class MenuNodeStore: ObservableObject {
    @Published var nodes: [MenuNodeCandidate]
    @Published var selectedNodeID: String

    @Published var isTestingAll = false
    @Published var testingNodeID: String?

    init(
        nodes: [MenuNodeCandidate] = [
            .init(id: "hk-1", name: "香港节点", region: "Hong Kong", latencyMs: 46),
            .init(id: "jp-1", name: "日本节点", region: "Japan", latencyMs: 78),
            .init(id: "sg-1", name: "新加坡节点", region: "Singapore", latencyMs: 63),
            .init(id: "us-1", name: "美国节点", region: "United States", latencyMs: 132),
        ],
        selectedNodeID: String = "hk-1"
    ) {
        self.nodes = nodes
        self.selectedNodeID = selectedNodeID
    }

    var selectedNode: MenuNodeCandidate? {
        nodes.first(where: { $0.id == selectedNodeID })
    }

    @MainActor
    func testAll() async {
        guard !isTestingAll else { return }
        isTestingAll = true
        testingNodeID = nil
        defer { isTestingAll = false }
        try? await Task.sleep(nanoseconds: 450_000_000)
        nodes = nodes.map { node in
            var copy = node
            let base = copy.latencyMs ?? 80
            let jitter = Int.random(in: -15...24)
            copy.latencyMs = max(1, base + jitter)
            return copy
        }
    }

    @MainActor
    func testOne(_ id: String) async {
        guard !isTestingAll, testingNodeID == nil else { return }
        testingNodeID = id
        defer { testingNodeID = nil }
        try? await Task.sleep(nanoseconds: 350_000_000)
        nodes = nodes.map { node in
            guard node.id == id else { return node }
            var copy = node
            let base = copy.latencyMs ?? 80
            let jitter = Int.random(in: -12...18)
            copy.latencyMs = max(1, base + jitter)
            return copy
        }
    }
}

struct MenuNodeCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let region: String
    var latencyMs: Int?

    var latencyText: String {
        guard let latencyMs else { return "—" }
        return "\(latencyMs) ms"
    }

    var latencyColor: Color {
        guard let latencyMs else { return .secondary }
        switch latencyMs {
        case ..<80: return .green
        case ..<160: return .orange
        default: return .red
        }
    }
}

struct MenuNodePickerWindowView: View {
    @ObservedObject var store: MenuNodeStore
    let vendorName: String

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
                .disabled(store.isTestingAll || store.testingNodeID != nil)
            }

            VStack(spacing: 8) {
                ForEach(store.nodes) { node in
                    nodeRow(node)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func nodeRow(_ node: MenuNodeCandidate) -> some View {
        let selected = (store.selectedNodeID == node.id)
        return HStack(spacing: 12) {
            Button {
                store.selectedNodeID = node.id
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? .accent : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(node.region)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(node.latencyText)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(node.latencyColor)
                .frame(width: 86, alignment: .trailing)

            Button {
                Task { await store.testOne(node.id) }
            } label: {
                if store.testingNodeID == node.id {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Label("测速", systemImage: "bolt.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.orange)
            .disabled(store.isTestingAll || store.testingNodeID != nil)
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
