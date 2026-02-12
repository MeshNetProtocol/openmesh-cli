import SwiftUI
import VPNLibrary

struct InstalledProvidersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var vpnController: VPNController

    @State private var isLoading = false
    @State private var errorText: String?

    @State private var installedItems: [InstalledProviderItem] = []
    @State private var providersByID: [String: TrafficProvider] = [:]
    @State private var selectedProviderForInstall: TrafficProvider?
    @State private var selectedProviderForDetail: ProviderDetailContext?
    @State private var uninstallTarget: InstalledProviderItem?

    var body: some View {
        ZStack {
            MarketIOSTheme.windowBackground(scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                Divider().opacity(0.30)
                content
            }
        }
        .navigationTitle("已安装")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") { dismiss() }
                    .tint(MarketIOSTheme.meshBlue)
            }
        }
        .sheet(item: $selectedProviderForInstall) { provider in
            ProviderInstallWizardView(provider: provider) {
                Task { await reloadAll() }
            }
        }
        .sheet(item: $selectedProviderForDetail) { detail in
            ProviderDetailHubView(
                context: detail,
                onAction: { action in
                    switch action {
                    case .install, .update, .reinstall:
                        selectedProviderForInstall = detail.provider
                    case .uninstall:
                        if let item = installedItemByID[detail.providerID] {
                            uninstallTarget = item
                        }
                    }
                }
            )
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
        VStack(spacing: 10) {
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
                .tint(MarketIOSTheme.meshBlue)
                .disabled(isLoading)
            }

            HStack(spacing: 8) {
                InstalledMetaPill(title: "已安装", value: "\(installedItems.count)", tint: MarketIOSTheme.meshBlue)
                InstalledMetaPill(title: "可更新", value: "\(updateCount)", tint: MarketIOSTheme.meshAmber)
                if orphanCount > 0 {
                    InstalledMetaPill(title: "离线条目", value: "\(orphanCount)", tint: MarketIOSTheme.meshRed)
                }
                Spacer(minLength: 0)
            }
        }
        .marketIOSCard(horizontal: 12, vertical: 10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                    .tint(MarketIOSTheme.meshBlue)
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
                    .buttonStyle(.borderedProminent)
                    .tint(MarketIOSTheme.meshBlue)
                Spacer()
            }
            .padding(.horizontal, 20)
        } else {
            List {
                if !installedItems.isEmpty {
                    HStack {
                        Text("共 \(installedItems.count) 个条目")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if updateCount > 0 {
                            Text("\(updateCount) 个可更新")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(MarketIOSTheme.meshAmber)
                        } else {
                            Text("均已同步")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(MarketIOSTheme.meshMint)
                        }
                    }
                    .listRowBackground(MarketIOSTheme.cardFill(scheme))
                }
                if installedItems.isEmpty {
                    Text("暂无已安装供应商")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installedItems) { item in
                        InstalledProviderRow(
                            item: item,
                            provider: providersByID[item.providerID],
                            onOpenDetail: {
                                selectedProviderForDetail = ProviderDetailContext(
                                    providerID: item.providerID,
                                    displayName: item.displayName,
                                    provider: providersByID[item.providerID],
                                    localHash: item.localPackageHash,
                                    pendingTags: item.pendingRuleSetTags
                                )
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .marketIOSListBackgroundHidden()
        }
    }

    private var updateCount: Int {
        installedItems.filter { item in
            guard !item.localPackageHash.isEmpty else { return false }
            guard let remote = providersByID[item.providerID]?.package_hash, !remote.isEmpty else { return false }
            return remote != item.localPackageHash
        }.count
    }

    private var orphanCount: Int {
        installedItems.filter { providersByID[$0.providerID] == nil }.count
    }

    private var installedItemByID: [String: InstalledProviderItem] {
        Dictionary(uniqueKeysWithValues: installedItems.map { ($0.providerID, $0) })
    }

    private func reloadAll() async {
        await MainActor.run {
            isLoading = true
            errorText = nil
        }
        do {
            let mapping = await SharedPreferences.installedProviderIDByProfile.get()
            let localHashes = await SharedPreferences.installedProviderPackageHash.get()
            let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
            let profiles = try await ProfileManager.list()

            let profileByID: [Int64: Profile] = Dictionary(uniqueKeysWithValues: profiles.compactMap { p in
                guard let id = p.id else { return nil }
                return (id, p)
            })

            var inferredProfileByProvider: [String: Int64] = [:]
            for profile in profiles {
                guard let pid = profile.id else { continue }
                guard let inferredProviderID = inferProviderID(fromProfilePath: profile.path) else { continue }
                if inferredProfileByProvider[inferredProviderID] == nil {
                    inferredProfileByProvider[inferredProviderID] = pid
                }
            }

            let providerIDs = Set(mapping.values)
                .union(localHashes.keys)
                .union(inferredProfileByProvider.keys)
            var rows: [InstalledProviderItem] = []
            for providerID in providerIDs {
                let profileID: Int64? =
                    mapping.first(where: { $0.value == providerID }).flatMap { Int64($0.key) }
                    ?? inferredProfileByProvider[providerID]
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

            let cachedProviders = MarketService.shared.getCachedMarketProviders()
            let cachedProviderMap = Dictionary(uniqueKeysWithValues: cachedProviders.map { ($0.id, $0) })

            await MainActor.run {
                installedItems = rows
                providersByID = cachedProviderMap
                isLoading = false
            }

            do {
                let providers = try await MarketService.shared.fetchMarketProvidersCached()
                let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
                await MainActor.run {
                    providersByID = providerMap
                    errorText = nil
                }
            } catch {
                let hasLocalRows = !rows.isEmpty
                let hasCachedProviders = !cachedProviderMap.isEmpty
                await MainActor.run {
                    if !hasLocalRows && !hasCachedProviders {
                        errorText = "加载已安装列表失败：\(error.localizedDescription)"
                    } else {
                        errorText = nil
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorText = "加载已安装列表失败：\(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func inferProviderID(fromProfilePath path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let marker = "/providers/"
        guard let providersRange = path.range(of: marker) else { return nil }
        let after = path[providersRange.upperBound...]
        guard let slash = after.firstIndex(of: "/") else { return nil }
        let providerID = String(after[..<slash])
        return providerID.isEmpty ? nil : providerID
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

private struct InstalledMetaPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14))
        .clipShape(Capsule(style: .continuous))
    }
}

private struct InstalledProviderRow: View {
    let item: InstalledProviderItem
    let provider: TrafficProvider?
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    if provider == nil {
                        MarketIOSChip(title: "Offline", tint: MarketIOSTheme.meshRed)
                    }
                    if updateAvailable {
                        MarketIOSChip(title: "Update", tint: MarketIOSTheme.meshAmber)
                    }
                    if !item.pendingRuleSetTags.isEmpty {
                        MarketIOSChip(title: "Init", tint: MarketIOSTheme.meshBlue)
                    }
                    Spacer(minLength: 0)
                }

                Text(item.providerID)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text("Local \(formattedHash(item.localPackageHash))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Remote \(formattedHash(remoteHash))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !item.pendingRuleSetTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.pendingRuleSetTags.prefix(4), id: \.self) { tag in
                            MarketIOSChip(title: tag, tint: MarketIOSTheme.meshBlue)
                        }
                    }
                }

                if provider == nil {
                    Text("该供应商未出现在当前在线市场，无法执行更新。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MarketIOSTheme.meshBlue)
        }
        .padding(.vertical, 2)
        .marketIOSCard(horizontal: 12, vertical: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetail()
        }
    }

    private var remoteHash: String {
        provider?.package_hash ?? ""
    }

    private var updateAvailable: Bool {
        guard !item.localPackageHash.isEmpty else { return false }
        guard !remoteHash.isEmpty else { return false }
        return remoteHash != item.localPackageHash
    }

    private func formattedHash(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "—" }
        if value.count <= 18 { return value }
        let prefix = value.prefix(10)
        let suffix = value.suffix(8)
        return "\(prefix)…\(suffix)"
    }
}

struct ProviderUninstallWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

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
            ZStack {
                MarketIOSTheme.windowBackground(scheme)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(providerName.isEmpty ? providerID : providerName)
                            .font(.headline)
                        Text(providerID)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .marketIOSCard(horizontal: 12, vertical: 10)

                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView {
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
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .marketIOSCard(horizontal: 12, vertical: 10)

                    if let errorText, !errorText.isEmpty {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(MarketIOSTheme.meshRed)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                uninstallFooter
            }
            .navigationTitle("卸载供应商")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if steps.isEmpty {
                    steps = UninstallStepState.defaultSteps()
                }
            }
        }
    }

    private var uninstallFooter: some View {
        HStack {
            Button("关闭") { dismiss() }
                .tint(MarketIOSTheme.meshBlue)
                .disabled(isRunning)
            Spacer()
            if finished {
                Button("完成") {
                    onFinished()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(MarketIOSTheme.meshBlue)
            } else {
                Button("开始卸载") {
                    Task { await runUninstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MarketIOSTheme.meshRed)
                .disabled(isRunning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                MarketIOSTheme.cardFill(scheme)
                Rectangle()
                    .fill(MarketIOSTheme.cardStroke(scheme))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: .bottom)
        )
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
                if let running = steps.firstIndex(where: { $0.status == .running }) {
                    steps[running].status = .failed
                    steps[running].message = error.localizedDescription
                } else if let firstPending = steps.firstIndex(where: { $0.status == .pending }) {
                    steps[firstPending].status = .failed
                    steps[firstPending].message = error.localizedDescription
                } else if let finalize = steps.firstIndex(where: { $0.id == .finalize }) {
                    steps[finalize].status = .failed
                    steps[finalize].message = "失败"
                }
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
            ProgressView()
                .tint(MarketIOSTheme.meshBlue)
                .scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MarketIOSTheme.meshMint)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(MarketIOSTheme.meshRed)
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
