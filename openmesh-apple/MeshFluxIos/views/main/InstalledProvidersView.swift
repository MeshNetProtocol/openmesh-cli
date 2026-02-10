import SwiftUI
import VPNLibrary

struct InstalledProvidersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vpnController: VPNController

    @State private var isLoading = false
    @State private var errorText: String?

    @State private var installedItems: [InstalledProviderItem] = []
    @State private var providersByID: [String: TrafficProvider] = [:]
    @State private var selectedProviderForInstall: TrafficProvider?
    @State private var uninstallTarget: InstalledProviderItem?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider().opacity(0.45)
            content
        }
        .navigationTitle("已安装")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") { dismiss() }
            }
        }
        .sheet(item: $selectedProviderForInstall) { provider in
            ProviderInstallWizardView(provider: provider) {
                Task { await reloadAll() }
            }
        }
        .sheet(item: $uninstallTarget) { item in
            ProviderUninstallWizardView(
                providerID: item.providerID,
                providerName: item.displayName,
                vpnConnected: vpnController.isConnected
            ) {
                Task { await reloadAll() }
            }
        }
        .task {
            await reloadAll()
        }
        .refreshable {
            await reloadAll()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("本地已安装 profile/provider 资产")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await reloadAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text("加载中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if let errorText, !errorText.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") { Task { await reloadAll() } }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.horizontal, 20)
        } else {
            List {
                if installedItems.isEmpty {
                    Text("暂无已安装供应商")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installedItems) { item in
                        InstalledProviderRow(
                            item: item,
                            provider: providersByID[item.providerID],
                            onReinstall: {
                                if let p = providersByID[item.providerID] {
                                    selectedProviderForInstall = p
                                }
                            },
                            onUpdate: {
                                if let p = providersByID[item.providerID] {
                                    selectedProviderForInstall = p
                                }
                            },
                            onUninstall: {
                                uninstallTarget = item
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func reloadAll() async {
        await MainActor.run {
            isLoading = true
            errorText = nil
        }
        do {
            let providers = try await MarketService.shared.fetchMarketProvidersCached()
            let mapping = await SharedPreferences.installedProviderIDByProfile.get()
            let localHashes = await SharedPreferences.installedProviderPackageHash.get()
            let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
            let profiles = try await ProfileManager.list()

            let profileByID: [Int64: Profile] = Dictionary(uniqueKeysWithValues: profiles.compactMap { p in
                guard let id = p.id else { return nil }
                return (id, p)
            })

            let providerIDs = Set(mapping.values).union(localHashes.keys)
            var rows: [InstalledProviderItem] = []
            for providerID in providerIDs {
                let profileID: Int64? = mapping.first(where: { $0.value == providerID }).flatMap { Int64($0.key) }
                let profileName: String = profileID.flatMap { profileByID[$0]?.name } ?? providerID
                rows.append(
                    InstalledProviderItem(
                        providerID: providerID,
                        profileID: profileID,
                        profileName: profileName,
                        localPackageHash: localHashes[providerID] ?? "",
                        pendingRuleSetTags: pending[providerID] ?? []
                    )
                )
            }
            rows.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })

            await MainActor.run {
                installedItems = rows
                providersByID = providerMap
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorText = "加载已安装列表失败：\(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

private struct InstalledProviderItem: Identifiable {
    var id: String { providerID }
    let providerID: String
    let profileID: Int64?
    let profileName: String
    let localPackageHash: String
    let pendingRuleSetTags: [String]

    var displayName: String { profileName }
}

private struct InstalledProviderRow: View {
    let item: InstalledProviderItem
    let provider: TrafficProvider?
    let onReinstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(item.providerID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if updateAvailable {
                        pill("Update", tint: .orange)
                    }
                    if !item.pendingRuleSetTags.isEmpty {
                        pill("Init", tint: .blue)
                    }
                }

                HStack(spacing: 10) {
                    Text("local: \(item.localPackageHash.isEmpty ? "—" : item.localPackageHash)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("remote: \(remoteHash.isEmpty ? "—" : remoteHash)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !item.pendingRuleSetTags.isEmpty {
                    Text("待初始化：\(item.pendingRuleSetTags.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if provider == nil {
                    Text("该供应商未出现在当前在线市场，无法执行更新。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button("Reinstall") { onReinstall() }
                    .buttonStyle(.bordered)
                    .disabled(provider == nil)

                Button("Update") { onUpdate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(provider == nil || !updateAvailable)

                Button("Uninstall") { onUninstall() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func pill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .cornerRadius(6)
            .foregroundStyle(tint)
    }

    private var remoteHash: String {
        provider?.package_hash ?? ""
    }

    private var updateAvailable: Bool {
        guard !item.localPackageHash.isEmpty else { return false }
        guard !remoteHash.isEmpty else { return false }
        return remoteHash != item.localPackageHash
    }
}

private struct ProviderUninstallWizardView: View {
    @Environment(\.dismiss) private var dismiss

    let providerID: String
    let providerName: String
    let vpnConnected: Bool
    let onFinished: () -> Void

    @State private var steps: [UninstallStepState] = []
    @State private var isRunning = false
    @State private var errorText: String?
    @State private var finished = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(providerName.isEmpty ? providerID : providerName)
                        .font(.headline)
                    Text(providerID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(steps) { s in
                        HStack(alignment: .top, spacing: 10) {
                            statusIcon(s.status)
                                .frame(width: 18, height: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title)
                                    .font(.subheadline.weight(.semibold))
                                if !s.message.isEmpty {
                                    Text(s.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                HStack {
                    Button("关闭") { dismiss() }
                        .disabled(isRunning)
                    Spacer()
                    if finished {
                        Button("完成") {
                            onFinished()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("开始卸载") {
                            Task { await runUninstall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                    }
                }
            }
            .padding(16)
            .navigationTitle("卸载供应商")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if steps.isEmpty {
                    steps = UninstallStepState.defaultSteps()
                }
            }
        }
    }

    private func runUninstall() async {
        await MainActor.run {
            errorText = nil
            finished = false
            isRunning = true
            steps = UninstallStepState.defaultSteps()
        }

        func update(_ id: ProviderUninstallStep, status: UninstallStatus, message: String) {
            if let idx = steps.firstIndex(where: { $0.id == id }) {
                steps[idx].status = status
                steps[idx].message = message
            }
        }

        do {
            await MainActor.run {
                update(.validate, status: .running, message: "检查当前连接状态")
            }
            try await ProviderUninstaller.uninstall(
                providerID: providerID,
                vpnConnected: vpnConnected,
                progress: { step, message in
                    Task { @MainActor in
                        for i in steps.indices {
                            if steps[i].status == .running, steps[i].id != step {
                                steps[i].status = .success
                            }
                        }
                        if let idx = steps.firstIndex(where: { $0.id == step }) {
                            steps[idx].status = step == .finalize ? .success : .running
                            steps[idx].message = message
                        }
                    }
                }
            )
            await MainActor.run {
                for i in steps.indices {
                    if steps[i].status == .running || steps[i].status == .pending {
                        steps[i].status = .success
                    }
                }
                finished = true
                isRunning = false
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
            }
        } catch {
            await MainActor.run {
                update(.finalize, status: .failed, message: "失败")
                errorText = error.localizedDescription
                isRunning = false
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: UninstallStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView().scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}

private enum UninstallStatus {
    case pending
    case running
    case success
    case failed
}

private struct UninstallStepState: Identifiable {
    var id: ProviderUninstallStep
    var title: String
    var message: String
    var status: UninstallStatus

    static func defaultSteps() -> [UninstallStepState] {
        [
            UninstallStepState(id: .validate, title: "校验状态", message: "", status: .pending),
            UninstallStepState(id: .removeProfile, title: "删除 Profile", message: "", status: .pending),
            UninstallStepState(id: .removePreferences, title: "清理映射", message: "", status: .pending),
            UninstallStepState(id: .removeFiles, title: "删除缓存文件", message: "", status: .pending),
            UninstallStepState(id: .finalize, title: "完成", message: "", status: .pending),
        ]
    }
}
