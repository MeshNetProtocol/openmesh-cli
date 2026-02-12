import SwiftUI
import VPNLibrary

struct ProviderMarketManagerView: View {
    @ObservedObject var vpnController: VPNController
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    @State private var tab: Tab = .marketplace
    @State private var isLoading = false
    @State private var errorText: String?

    @State private var query: String = ""
    @State private var region: String = "全部"
    @State private var sort: Sort = .updatedDesc

    @State private var allProviders: [TrafficProvider] = []
    @State private var installed: [InstalledProvider] = []

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                Divider().overlay(MeshFluxTheme.meshBlue.opacity(0.16))
                toolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider().overlay(MeshFluxTheme.meshBlue.opacity(0.12))
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reloadAll() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("供应商市场")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MeshFluxTheme.meshBlue, MeshFluxTheme.meshCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(tab == .marketplace ? "搜索、排序、安装/更新供应商" : "管理本地已安装的供应商")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $tab) {
                Text("Marketplace").tag(Tab.marketplace)
                Text("Installed").tag(Tab.installed)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .tint(MeshFluxTheme.meshBlue)
            Button("关闭") { onClose() }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshAmber)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("搜索（名称/作者/标签/简介）", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)

                Picker("地区", selection: $region) {
                    ForEach(regionOptions, id: \.self) { r in
                        Text(r).tag(r)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.55))
                )
                .frame(width: 130)

                Picker("排序", selection: $sort) {
                    Text("更新时间↓").tag(Sort.updatedDesc)
                    Text("价格↑（USD/GB）").tag(Sort.priceAsc)
                    Text("价格↓（USD/GB）").tag(Sort.priceDesc)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.55))
                )
                .frame(width: 170)

                Spacer(minLength: 4)

                Button("刷新") {
                    Task { await reloadAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshBlue)
                .disabled(isLoading)
            }
            .controlSize(.small)

            HStack(spacing: 6) {
                MarketMetaPill(title: tab == .marketplace ? "Market" : "Installed", value: "\(displayedCount)/\(totalCount)")
                if region != "全部" {
                    MarketMetaPill(title: "Region", value: region)
                }
                if !trimmedQuery.isEmpty {
                    MarketMetaPill(title: "Query", value: "“\(trimmedQuery)”")
                }
                MarketMetaPill(title: "Sort", value: sortDisplayName)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private var content: some View {
        Group {
            if isLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .tint(MeshFluxTheme.meshBlue)
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
                        .tint(MeshFluxTheme.meshBlue)
                    Spacer()
                }
            } else {
                if tab == .marketplace {
                    providerList(filteredSortedProviders)
                } else {
                    installedList(filteredInstalled)
                }
            }
        }
    }

    private func providerList(_ providers: [TrafficProvider]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                if providers.isEmpty {
                    Text("没有匹配的供应商")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }
                ForEach(providers) { p in
                    ProviderMarketRow(
                        provider: p,
                        localHash: localHash(providerID: p.id),
                        pendingTags: pendingTags(providerID: p.id),
                        onInstallOrUpdate: { showInstallWizard(provider: p) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func installedList(_ items: [InstalledProvider]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                if items.isEmpty {
                    Text("暂无已安装供应商")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }
                ForEach(items) { item in
                    InstalledProviderRow(
                        item: item,
                        remoteHash: allProviders.first(where: { $0.id == item.providerID })?.package_hash ?? "",
                        onReinstall: {
                            if let p = allProviders.first(where: { $0.id == item.providerID }) {
                                showInstallWizard(provider: p)
                            }
                        },
                        onUpdate: {
                            if let p = allProviders.first(where: { $0.id == item.providerID }) {
                                showInstallWizard(provider: p)
                            }
                        },
                        onUninstall: {
                            ProviderUninstallWindowManager.shared.show(
                                vpnController: vpnController,
                                providerID: item.providerID,
                                providerName: item.displayName,
                                onFinished: {
                                    Task { await reloadAll() }
                                }
                            )
                        }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func showInstallWizard(provider: TrafficProvider) {
        ProviderInstallWindowManager.shared.show(provider: provider) { isInstalling in
            if !isInstalling {
                Task { await reloadAll() }
            }
        }
    }

    private func reloadAll() async {
        isLoading = true
        errorText = nil
        do {
            let providers = (try? await MarketService.shared.fetchMarketProvidersCached()) ?? []
            let installed = try await loadInstalledProviders()
            await MainActor.run {
                self.allProviders = providers
                self.installed = installed
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorText = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func loadInstalledProviders() async throws -> [InstalledProvider] {
        let mapping = await SharedPreferences.installedProviderIDByProfile.get()
        let localHashes = await SharedPreferences.installedProviderPackageHash.get()
        let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()

        let profiles = try await ProfileManager.list()
        let profileByID: [Int64: Profile] = Dictionary(uniqueKeysWithValues: profiles.compactMap { p in
            guard let id = p.id else { return nil }
            return (id, p)
        })

        var rows: [InstalledProvider] = []
        let providerIDs = Set(mapping.values).union(localHashes.keys)
        for providerID in providerIDs {
            let profileID: Int64? = mapping.first(where: { $0.value == providerID }).flatMap { Int64($0.key) }
            let profileName: String = profileID.flatMap { profileByID[$0]?.name } ?? providerID
            rows.append(
                InstalledProvider(
                    providerID: providerID,
                    profileID: profileID,
                    profileName: profileName,
                    localPackageHash: localHashes[providerID] ?? "",
                    pendingRuleSetTags: pending[providerID] ?? []
                )
            )
        }
        return rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func localHash(providerID: String) -> String {
        installed.first(where: { $0.providerID == providerID })?.localPackageHash ?? ""
    }

    private func pendingTags(providerID: String) -> [String] {
        installed.first(where: { $0.providerID == providerID })?.pendingRuleSetTags ?? []
    }

    private var filteredSortedProviders: [TrafficProvider] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = allProviders.filter { p in
            if region != "全部" && !tagsMatchRegion(p.tags, region: region) { return false }
            if q.isEmpty { return true }
            let hay = ([p.id, p.name, p.author, p.description] + p.tags).joined(separator: " ").lowercased()
            return hay.contains(q)
        }
        switch sort {
        case .updatedDesc:
            return filtered.sorted { $0.updated_at > $1.updated_at }
        case .priceAsc:
            return filtered.sorted { ($0.price_per_gb_usd ?? Double.greatestFiniteMagnitude) < ($1.price_per_gb_usd ?? Double.greatestFiniteMagnitude) }
        case .priceDesc:
            return filtered.sorted { ($0.price_per_gb_usd ?? -1) > ($1.price_per_gb_usd ?? -1) }
        }
    }

    private var filteredInstalled: [InstalledProvider] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return installed.filter { i in
            if region != "全部" && !tagsMatchRegion(allProviders.first(where: { $0.id == i.providerID })?.tags ?? [], region: region) {
                return false
            }
            if q.isEmpty { return true }
            let hay = ([i.providerID, i.profileName, i.localPackageHash] + i.pendingRuleSetTags).joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    private var regionOptions: [String] {
        var regions: Set<String> = ["全部"]
        for p in allProviders {
            for t in p.tags {
                if let r = normalizeRegionTag(t) {
                    regions.insert(r)
                }
            }
        }
        return Array(regions).sorted { a, b in
            if a == "全部" { return true }
            if b == "全部" { return false }
            return a < b
        }
    }

    private func tagsMatchRegion(_ tags: [String], region: String) -> Bool {
        guard region != "全部" else { return true }
        return tags.contains { normalizeRegionTag($0) == region }
    }

    private func normalizeRegionTag(_ tag: String) -> String? {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("region:") {
            let v = t.dropFirst("region:".count).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return v.isEmpty ? nil : v
        }
        if t.count == 2, t.uppercased() == t, t.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil {
            return t
        }
        return nil
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedCount: Int {
        tab == .marketplace ? filteredSortedProviders.count : filteredInstalled.count
    }

    private var totalCount: Int {
        tab == .marketplace ? allProviders.count : installed.count
    }

    private var sortDisplayName: String {
        switch sort {
        case .updatedDesc:
            return "更新时间"
        case .priceAsc:
            return "价格↑"
        case .priceDesc:
            return "价格↓"
        }
    }
}

private enum Tab: String {
    case marketplace
    case installed
}

private enum Sort: String {
    case updatedDesc
    case priceAsc
    case priceDesc
}

private struct InstalledProvider: Identifiable {
    var id: String { providerID }
    let providerID: String
    let profileID: Int64?
    let profileName: String
    let localPackageHash: String
    let pendingRuleSetTags: [String]

    var displayName: String { profileName }
}

private struct ProviderMarketRow: View {
    @Environment(\.colorScheme) private var scheme
    let provider: TrafficProvider
    let localHash: String
    let pendingTags: [String]
    let onInstallOrUpdate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            buttonTint.opacity(0.8),
                            buttonTint.opacity(0.2),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .semibold))
                    if isUpdateAvailable {
                        MarketBadge(title: "Update", color: MeshFluxTheme.meshAmber)
                    } else if isInstalled {
                        MarketBadge(title: "Installed", color: MeshFluxTheme.meshMint)
                    }
                    if !pendingTags.isEmpty {
                        MarketBadge(title: "Init", color: MeshFluxTheme.meshBlue)
                    }
                }
                Text(provider.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(provider.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let p = provider.price_per_gb_usd {
                        Text(String(format: "%.2f USD/GB", p))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(provider.updated_at)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !provider.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(provider.tags.prefix(6), id: \.self) { tag in
                            MarketTagChip(title: tag)
                        }
                    }
                }
            }
            Spacer()
            MarketActionButton(title: actionTitle, tint: buttonTint, action: onInstallOrUpdate)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
        .shadow(color: MeshFluxTheme.meshBlue.opacity(scheme == .dark ? 0.14 : 0.06), radius: 8, x: 0, y: 4)
    }

    private var isInstalled: Bool {
        !localHash.isEmpty
    }

    private var isUpdateAvailable: Bool {
        guard let remoteHash = provider.package_hash, !remoteHash.isEmpty else { return false }
        guard !localHash.isEmpty else { return false }
        return remoteHash != localHash
    }

    private var actionTitle: String {
        if isUpdateAvailable { return "Update" }
        if isInstalled { return "Reinstall" }
        return "Install"
    }

    private var buttonTint: Color {
        if actionTitle == "Update" { return MeshFluxTheme.meshAmber }
        if actionTitle == "Reinstall" { return MeshFluxTheme.meshCyan }
        return MeshFluxTheme.meshBlue
    }
}

private struct InstalledProviderRow: View {
    @Environment(\.colorScheme) private var scheme
    let item: InstalledProvider
    let remoteHash: String
    let onReinstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            updateAvailable ? MeshFluxTheme.meshAmber.opacity(0.75) : MeshFluxTheme.meshMint.opacity(0.75),
                            MeshFluxTheme.meshBlue.opacity(0.25),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.providerID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if updateAvailable {
                        MarketBadge(title: "Update", color: MeshFluxTheme.meshAmber)
                    }
                    if !item.pendingRuleSetTags.isEmpty {
                        MarketBadge(title: "Init", color: MeshFluxTheme.meshBlue)
                    }
                }
                HStack(spacing: 10) {
                    Text("local: \(item.localPackageHash.isEmpty ? "—" : item.localPackageHash)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("remote: \(remoteHash.isEmpty ? "—" : remoteHash)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !item.pendingRuleSetTags.isEmpty {
                    Text("待初始化：\(item.pendingRuleSetTags.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    MarketActionButton(title: "Reinstall", tint: MeshFluxTheme.meshCyan, action: onReinstall)
                    MarketActionButton(title: "Update", tint: MeshFluxTheme.meshAmber, action: onUpdate)
                        .disabled(!updateAvailable)
                }
                MarketActionButton(title: "Uninstall", tint: Color(red: 0.88, green: 0.30, blue: 0.36), action: onUninstall)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
        .shadow(color: MeshFluxTheme.meshBlue.opacity(scheme == .dark ? 0.12 : 0.06), radius: 8, x: 0, y: 4)
    }

    private var updateAvailable: Bool {
        guard !item.localPackageHash.isEmpty else { return false }
        guard !remoteHash.isEmpty else { return false }
        return remoteHash != item.localPackageHash
    }
}

private struct MarketBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.28), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
            .foregroundStyle(color)
    }
}

private struct MarketTagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(MeshFluxTheme.meshBlue.opacity(0.1))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(MeshFluxTheme.meshBlue.opacity(0.24), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
            .foregroundStyle(.secondary)
    }
}

private struct MarketActionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.74)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.3), radius: 6, x: 0, y: 3)
    }
}

private struct MarketMetaPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MeshFluxTheme.meshBlue.opacity(0.10))
        .overlay(
            Capsule(style: .continuous)
                .stroke(MeshFluxTheme.meshBlue.opacity(0.22), lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
    }
}
