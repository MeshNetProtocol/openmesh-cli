import SwiftUI
import VPNLibrary

struct ProviderMarketplaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var vpnController: VPNController

    @State private var query: String = ""
    @State private var region: String = "全部"
    @State private var sort: Sort = .updatedDesc

    @State private var allProviders: [TrafficProvider] = []
    @State private var installedPackageHashByProvider: [String: String] = [:]
    @State private var pendingRuleSetsByProvider: [String: [String]] = [:]
    @State private var updatesAvailable: [String: Bool] = [:]

    @State private var isLoading = false
    @State private var errorText: String?
    @State private var cacheNotice: String?
    @State private var selectedProviderForInstall: TrafficProvider?
    @State private var selectedProviderForDetail: ProviderDetailContext?
    @State private var uninstallTarget: ProviderUninstallSelection?
    @State private var hasLoadedInitially = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            MarketIOSTheme.windowBackground(scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                Divider().opacity(0.30)
                content
            }
        }
        .onTapGesture {
            searchFocused = false
        }
        .navigationTitle("供应商市场")
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
                    selectedProviderForDetail = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        switch action {
                        case .install, .update, .reinstall:
                            selectedProviderForInstall = detail.provider
                        case .uninstall:
                            uninstallTarget = ProviderUninstallSelection(
                                providerID: detail.providerID,
                                providerName: detail.displayName
                            )
                        }
                    }
                }
            )
        }
        .sheet(item: $uninstallTarget) { item in
            ProviderUninstallWizardView(
                providerID: item.providerID,
                providerName: item.providerName,
                vpnConnected: vpnController.isConnected
            ) {
                Task { await reloadAll() }
            }
        }
        .task {
            if !hasLoadedInitially {
                hasLoadedInitially = true
                await reloadAll(reason: "initial")
            } else {
                NSLog("ProviderMarketplaceView: skip initial reload (already loaded)")
            }
        }
        .refreshable {
            await reloadAll(reason: "pull-to-refresh")
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            Task { await reloadAll(reason: "notification") }
        }
        .onReceive(NotificationCenter.default.publisher(for: MarketService.shared.providerUpdateStateDidChangeNotification)) { _ in
            Task {
                let updates = await SharedPreferences.providerUpdatesAvailable.get()
                await MainActor.run { updatesAvailable = updates }
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MarketIOSChip(title: "在线 \(allProviders.count)", tint: MarketIOSTheme.meshBlue)
                MarketIOSChip(title: "命中 \(filteredSortedProviders.count)", tint: MarketIOSTheme.meshCyan)
                Menu {
                    ForEach(regionOptions, id: \.self) { r in
                        Button(r) { region = r }
                    }
                } label: {
                    MarketIOSChip(title: region == "全部" ? "全地区" : "地区 \(region)", tint: MarketIOSTheme.meshMint)
                }
                Menu {
                    Button("更新时间↓") { sort = .updatedDesc }
                    Button("价格↑（USD/GB）") { sort = .priceAsc }
                    Button("价格↓（USD/GB）") { sort = .priceDesc }
                } label: {
                    MarketIOSChip(title: sortLabel, tint: MarketIOSTheme.meshBlue)
                }
                Spacer(minLength: 0)
                if let cacheNotice, !cacheNotice.isEmpty {
                    Text(cacheNotice)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("搜索名称/作者/标签/简介", text: $query)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .focused($searchFocused)
                        .submitLabel(.done)
                        .onSubmit { searchFocused = false }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MarketIOSTheme.cardFill(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                )

                Button {
                    Task { await reloadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(MarketIOSTheme.cardFill(scheme))
                )
                .overlay(
                    Circle()
                        .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                )
                .tint(MarketIOSTheme.meshBlue)
                .disabled(isLoading)
            }
        }
        .marketIOSCard(horizontal: 12, vertical: 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && allProviders.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .tint(MarketIOSTheme.meshBlue)
                Text("正在搜索供应商市场…")
                    .font(.subheadline)
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
                if filteredSortedProviders.isEmpty {
                    Text("没有匹配的供应商")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredSortedProviders) { provider in
                        ProviderMarketRow(
                            provider: provider,
                            localHash: installedPackageHashByProvider[provider.id] ?? "",
                            pendingTags: pendingRuleSetsByProvider[provider.id] ?? [],
                            updateAvailable: updatesAvailable[provider.id] == true,
                            onOpenDetail: {
                                selectedProviderForDetail = ProviderDetailContext(
                                    providerID: provider.id,
                                    displayName: provider.name,
                                    provider: provider,
                                    localHash: installedPackageHashByProvider[provider.id] ?? "",
                                    pendingTags: pendingRuleSetsByProvider[provider.id] ?? [],
                                    updateAvailable: updatesAvailable[provider.id] == true
                                )
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .marketIOSListBackgroundHidden()
            .dismissKeyboardOnScrollIfAvailable()
            .overlay(alignment: .top) {
                if isLoading && !allProviders.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在同步服务器信息...")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(MarketIOSTheme.meshBlue.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.top, 10)
                }
            }
        }
    }

    private func reloadAll(reason: String = "manual") async {
        let localHash = await SharedPreferences.installedProviderPackageHash.get()
        let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
        let updates = await SharedPreferences.providerUpdatesAvailable.get()

        let currentlyLoading = await MainActor.run { isLoading }
        if currentlyLoading {
            // Still update local data association even if already loading market
            await MainActor.run {
                self.installedPackageHashByProvider = localHash
                self.pendingRuleSetsByProvider = pending
                self.updatesAvailable = updates
            }
            NSLog("ProviderMarketplaceView: updated local state only (already loading). reason=%@", reason)
            return
        }
        NSLog("ProviderMarketplaceView: reload start. reason=%@", reason)

        let cachedProviders = MarketService.shared.getCachedMarketProviders()
        if !cachedProviders.isEmpty {
            await MainActor.run {
                allProviders = cachedProviders
                installedPackageHashByProvider = localHash
                pendingRuleSetsByProvider = pending
                updatesAvailable = updates
                errorText = nil
                cacheNotice = "正在刷新在线数据，当前先显示本地缓存。"
            }
            NSLog("ProviderMarketplaceView: applied cached providers first. count=%ld reason=%@", cachedProviders.count, reason)
        }

        let shouldBlockWithLoading = await MainActor.run { allProviders.isEmpty }
        await MainActor.run {
            isLoading = shouldBlockWithLoading
            errorText = nil
        }
        do {
            let providers = try await MarketService.shared.fetchMarketProvidersCached()
            let refreshedLocalHash = await SharedPreferences.installedProviderPackageHash.get()
            let refreshedPending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
            let refreshedUpdates = await SharedPreferences.providerUpdatesAvailable.get()

            await MainActor.run {
                allProviders = providers
                installedPackageHashByProvider = refreshedLocalHash
                pendingRuleSetsByProvider = refreshedPending
                updatesAvailable = refreshedUpdates
                isLoading = false
                cacheNotice = nil
            }
            NSLog("ProviderMarketplaceView: reload success. providers=%ld reason=%@", providers.count, reason)
        } catch {
            NSLog("ProviderMarketplaceView: reload failed. reason=%@ error=%@", reason, String(describing: error))
            let recommendedFallback = MarketService.shared.getCachedRecommendedProviders()
            await MainActor.run {
                if allProviders.isEmpty {
                    if !recommendedFallback.isEmpty {
                        allProviders = recommendedFallback
                        errorText = nil
                        cacheNotice = "在线市场请求失败，当前显示推荐缓存（可能不完整）。"
                    } else {
                        errorText = "加载供应商市场失败：\(error.localizedDescription)"
                        cacheNotice = nil
                    }
                } else {
                    errorText = nil
                    cacheNotice = "网络请求失败，当前显示本地缓存数据。"
                }
                isLoading = false
            }
        }
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

    private var sortLabel: String {
        switch sort {
        case .updatedDesc:
            return "按更新时间"
        case .priceAsc:
            return "按价格升序"
        case .priceDesc:
            return "按价格降序"
        }
    }
}

private extension View {
    @ViewBuilder
    func dismissKeyboardOnScrollIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.immediately)
        } else {
            self
        }
    }
}

private enum Sort: String {
    case updatedDesc
    case priceAsc
    case priceDesc
}

struct ProviderDetailContext: Identifiable {
    var id: String { providerID }
    let providerID: String
    let displayName: String
    let provider: TrafficProvider?
    let localHash: String
    let pendingTags: [String]
    let updateAvailable: Bool
}

enum ProviderDetailAction: CaseIterable {
    case install
    case update
    case reinstall
    case uninstall

    var title: String {
        switch self {
        case .install: return "安装"
        case .update: return "更新"
        case .reinstall: return "重装"
        case .uninstall: return "卸载"
        }
    }

    var icon: String {
        switch self {
        case .install: return "arrow.down.circle.fill"
        case .update: return "arrow.triangle.2.circlepath.circle.fill"
        case .reinstall: return "shippingbox.circle.fill"
        case .uninstall: return "trash.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .install: return MarketIOSTheme.meshBlue
        case .update: return MarketIOSTheme.meshAmber
        case .reinstall: return MarketIOSTheme.meshCyan
        case .uninstall: return MarketIOSTheme.meshRed
        }
    }
}

private struct ProviderUninstallSelection: Identifiable {
    var id: String { providerID }
    let providerID: String
    let providerName: String
}

private struct MarketMetaPill: View {
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

private struct ProviderMarketRow: View {
    let provider: TrafficProvider
    let localHash: String
    let pendingTags: [String]
    let updateAvailable: Bool
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if let status = statusBadgeTitle {
                            Text(status)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(statusTint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(statusTint.opacity(0.12))
                                )
                        }
                        if let p = provider.price_per_gb_usd {
                            Text(String(format: "$%.2f/GB", p))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MarketIOSTheme.meshCyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(MarketIOSTheme.meshCyan.opacity(0.12))
                                )
                        }
                    }
                }

                Text(provider.description)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(provider.author, systemImage: "person")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Label(updatedAtLabel, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !provider.tags.isEmpty {
                    Text(tagSummary)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MarketIOSTheme.meshBlue)
            }
        }
        .padding(.vertical, 2)
        .marketIOSCard(horizontal: 12, vertical: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetail()
        }
    }

    private var statusBadgeTitle: String? {
        if updateAvailable { return "Update" }
        if isInstalled { return "Installed" }
        if !pendingTags.isEmpty { return "Init" }
        return nil
    }

    private var statusTint: Color {
        if updateAvailable { return MarketIOSTheme.meshAmber }
        if isInstalled { return MarketIOSTheme.meshMint }
        return MarketIOSTheme.meshBlue
    }

    private var tagSummary: String {
        let trimmed = provider.tags.prefix(4)
        let joined = trimmed.joined(separator: " · ")
        return "标签: \(joined)"
    }

    private var updatedAtLabel: String {
        let trimmed = provider.updated_at.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "unknown" }
        if trimmed.count >= 10 { return String(trimmed.prefix(10)) }
        return trimmed
    }

    private var isInstalled: Bool {
        !localHash.isEmpty
    }
}

struct ProviderDetailHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let context: ProviderDetailContext
    let onAction: (ProviderDetailAction) -> Void

    var body: some View {
        ZStack {
            MarketIOSTheme.windowBackground(scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard
                    descriptionCard
                    metaCard
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionFooter
        }
        .navigationTitle("供应商详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") { dismiss() }
                    .tint(MarketIOSTheme.meshBlue)
            }
        }
    }

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MarketIOSTheme.cardFill(scheme),
                            MarketIOSTheme.meshBlue.opacity(scheme == .dark ? 0.14 : 0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [MarketIOSTheme.meshBlue, MarketIOSTheme.meshIndigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PROVIDER DETAIL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(MarketIOSTheme.meshCyan)
                        Text(context.displayName)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(context.providerID)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack(spacing: 8) {
                    if context.updateAvailable {
                        MarketIOSChip(title: "可更新", tint: MarketIOSTheme.meshAmber)
                    } else if isInstalled {
                        MarketIOSChip(title: "已安装", tint: MarketIOSTheme.meshMint)
                    } else {
                        MarketIOSChip(title: "未安装", tint: MarketIOSTheme.meshBlue)
                    }
                    if !isMarketAvailable {
                        MarketIOSChip(title: "市场离线", tint: MarketIOSTheme.meshRed)
                    }
                    if let p = context.provider?.price_per_gb_usd {
                        MarketIOSChip(title: String(format: "%.2f USD/GB", p), tint: MarketIOSTheme.meshCyan)
                    }
                }

                if !isMarketAvailable {
                    Label("当前供应商不在在线市场，仅可执行本地卸载", systemImage: "info.circle")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("简介", systemImage: "text.alignleft")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(descriptionText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineSpacing(3)
                .foregroundStyle(.primary)
        }
        .marketIOSCard(horizontal: 14, vertical: 14)
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("元数据", systemImage: "square.grid.2x2")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 8
            ) {
                metricTile("作者", value: context.provider?.author ?? "Unknown")
                metricTile("更新时间", value: updatedDateLabel)
                metricTile("本地 Hash", value: formattedHash(context.localHash), monospaced: true)
                metricTile("远端 Hash", value: formattedHash(remoteHash), monospaced: true)
            }

            if !context.pendingTags.isEmpty {
                Text(pendingTagSummary)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let tags = context.provider?.tags, !tags.isEmpty {
                Text(tagSummary(tags))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .marketIOSCard(horizontal: 12, vertical: 12)
    }

    private func metricTile(_ title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: monospaced ? .monospaced : .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarketIOSTheme.chipFill(MarketIOSTheme.meshBlue, scheme: scheme))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MarketIOSTheme.chipStroke(MarketIOSTheme.meshBlue, scheme: scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionFooter: some View {
        VStack(spacing: 10) {
            if let primaryAction {
                Button {
                    dismiss()
                    onAction(primaryAction)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: primaryAction.icon)
                            .font(.system(size: 15, weight: .bold))
                        Text(primaryAction.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [primaryAction.tint, primaryAction.tint.opacity(0.86)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if secondaryActions.count == 1, let onlyAction = secondaryActions.first {
                HStack(spacing: 10) {
                    Button("关闭") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(MarketIOSTheme.meshBlue)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MarketIOSTheme.cardFill(scheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                        )

                    detailAction(onlyAction, compact: false)
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 10) {
                    Button("关闭") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(MarketIOSTheme.meshBlue)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MarketIOSTheme.cardFill(scheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                        )

                    if !secondaryActions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(secondaryActions, id: \.self) { action in
                                    detailAction(action, compact: true)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                        .frame(maxWidth: 220)
                    } else if availableActions.isEmpty {
                        Text("当前无可执行操作")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
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

    private func detailAction(_ action: ProviderDetailAction, compact: Bool = false) -> some View {
        Button {
            dismiss()
            onAction(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 12, weight: .bold))
                Text(action.title)
                    .font(.system(size: compact ? 12 : 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, compact ? 10 : 11)
            .padding(.vertical, compact ? 7 : 8)
            .frame(minWidth: compact ? 80 : 110, minHeight: compact ? 36 : 40)
            .foregroundStyle(action == primaryAction ? Color.white : action.tint)
            .background(
                Group {
                    if action == primaryAction {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [action.tint, action.tint.opacity(0.84)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(MarketIOSTheme.chipFill(action.tint, scheme: scheme))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(action.tint.opacity(action == primaryAction ? 0.20 : 0.34), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var isInstalled: Bool {
        !context.localHash.isEmpty
    }

    private var isMarketAvailable: Bool {
        context.provider != nil
    }

    private var remoteHash: String {
        context.provider?.package_hash ?? ""
    }

    private var hasRemoteSource: Bool {
        !remoteHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableActions: [ProviderDetailAction] {
        var actions: [ProviderDetailAction] = []
        if !isInstalled && hasRemoteSource {
            actions.append(.install)
        }
        if context.updateAvailable {
            actions.append(.update)
        }
        if isInstalled && hasRemoteSource {
            actions.append(.reinstall)
        }
        if isInstalled {
            actions.append(.uninstall)
        }
        return actions
    }

    private var primaryAction: ProviderDetailAction? {
        if availableActions.contains(.install) { return .install }
        if availableActions.contains(.update) { return .update }
        if availableActions.contains(.reinstall) { return .reinstall }
        if availableActions.contains(.uninstall) { return .uninstall }
        return nil
    }

    private var secondaryActions: [ProviderDetailAction] {
        guard let primaryAction else { return availableActions }
        return availableActions.filter { $0 != primaryAction }
    }

    private var updatedDateLabel: String {
        let raw = context.provider?.updated_at.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "—" }
        if raw.count >= 10 { return String(raw.prefix(10)) }
        return raw
    }

    private var descriptionText: String {
        context.provider?.description ?? "该供应商当前不在在线市场中，仍可管理本地安装状态。"
    }

    private func formattedHash(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "—" }
        if value.count <= 20 { return value }
        return "\(value.prefix(10))…\(value.suffix(8))"
    }

    private var pendingTagSummary: String {
        let trimmed = context.pendingTags.prefix(4)
        let joined = trimmed.joined(separator: " · ")
        return "待初始化: \(joined)"
    }

    private func tagSummary(_ tags: [String]) -> String {
        let trimmed = tags.prefix(5)
        let joined = trimmed.joined(separator: " · ")
        return "标签: \(joined)"
    }
}

struct ProviderInstallWizardView: View {
    struct StepState: Identifiable {
        enum Status {
            case pending
            case running
            case success
            case failure
        }

        let id: MarketService.InstallStep
        var title: String
        var status: Status
        var message: String?
    }

    // Wrapper to avoid SwiftUI reflection crash on complex async closure types
    class ActionWrapper {
        let action: ((_ selectAfterInstall: Bool, _ progress: @escaping @Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)?
        init(_ action: ((_ selectAfterInstall: Bool, _ progress: @escaping @Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)?) {
            self.action = action
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let provider: TrafficProvider
    let installActionWrapper: ActionWrapper
    let onCompleted: () -> Void

    @State private var steps: [StepState] = []
    @State private var isRunning = false
    @State private var selectAfterInstall = true
    @State private var errorText: String?
    @State private var finished = false
    @State private var currentRunningStep: MarketService.InstallStep?

    init(
        provider: TrafficProvider,
        installAction: ((_ selectAfterInstall: Bool, _ progress: @escaping @Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)? = nil,
        onCompleted: @escaping () -> Void
    ) {
        self.provider = provider
        self.installActionWrapper = ActionWrapper(installAction)
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationView {
            ZStack {
                MarketIOSTheme.windowBackground(scheme)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(provider.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("安装配置与规则集，并可自动切换到该供应商")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Toggle("安装完成后切换到该供应商", isOn: $selectAfterInstall)
                            .tint(MarketIOSTheme.meshBlue)
                            .disabled(isRunning || finished)
                    }
                    .marketIOSCard(horizontal: 12, vertical: 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(steps) { step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(symbol(for: step.status))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(statusColor(step.status))
                                        .frame(width: 20, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.title)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        if let message = step.message, !message.isEmpty {
                                            Text(message)
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .marketIOSCard(horizontal: 12, vertical: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(MarketIOSTheme.meshRed)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                installFooter
            }
            .navigationTitle("安装供应商")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if steps.isEmpty {
                    steps = defaultSteps()
                }
            }
        }
    }

    private var installFooter: some View {
        VStack(spacing: 10) {
            if finished {
                Button("完成") {
                    onCompleted()
                    dismiss()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MarketIOSTheme.meshBlue, MarketIOSTheme.meshBlue.opacity(0.86)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .buttonStyle(.plain)
            } else if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(MarketIOSTheme.meshBlue)
                        .scaleEffect(0.9)
                    Text(runningHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MarketIOSTheme.cardFill(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                )
            } else {
                Button(errorText == nil ? "开始安装" : "重试") {
                    Task { await runInstall() }
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MarketIOSTheme.meshBlue, MarketIOSTheme.meshBlue.opacity(0.86)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .buttonStyle(.plain)
            }

            Button("关闭") { dismiss() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(MarketIOSTheme.meshBlue)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MarketIOSTheme.cardFill(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                )
                .disabled(isRunning)
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

    private func defaultSteps() -> [StepState] {
        [
            .init(id: .fetchDetail, title: "读取供应商详情", status: .pending, message: nil),
            .init(id: .downloadConfig, title: "下载配置文件", status: .pending, message: nil),
            .init(id: .validateConfig, title: "解析配置文件", status: .pending, message: nil),
            .init(id: .downloadRoutingRules, title: "下载 routing_rules.json（可选）", status: .pending, message: nil),
            .init(id: .writeRoutingRules, title: "写入 routing_rules.json（可选）", status: .pending, message: nil),
            .init(id: .downloadRuleSet, title: "下载 rule-set（可选）", status: .pending, message: nil),
            .init(id: .writeRuleSet, title: "写入 rule-set（可选）", status: .pending, message: nil),
            .init(id: .writeConfig, title: "写入 config.json", status: .pending, message: nil),
            .init(id: .registerProfile, title: "注册到供应商列表", status: .pending, message: nil),
            .init(id: .finalize, title: "完成", status: .pending, message: nil),
        ]
    }

    private func runInstall() async {
        let startedAt = Date()
        NSLog("ProviderInstallWizardView(iOS): runInstall start provider=%@", provider.id)
        await MainActor.run {
            errorText = nil
            finished = false
            isRunning = true
            currentRunningStep = nil
            for i in steps.indices {
                steps[i].status = .pending
                steps[i].message = nil
            }
        }

        func update(step: MarketService.InstallStep, message: String) {
            if currentRunningStep != step {
                if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                    steps[runningIndex].status = .success
                }
                currentRunningStep = step
            }
            if let idx = steps.firstIndex(where: { $0.id == step }) {
                steps[idx].status = .running
                steps[idx].message = message
            }
        }

        do {
            await MainActor.run {
                update(step: .fetchDetail, message: "开始安装")
            }
            let progressHandler: @Sendable (MarketService.InstallProgress) -> Void = { p in
                Task { @MainActor in
                    update(step: p.step, message: p.message)
                }
            }
            if let installAction = installActionWrapper.action {
                try await installAction(selectAfterInstall, progressHandler)
            } else {
                let providerToInstall = provider
                try await Task.detached(priority: .userInitiated) {
                    try await MarketService.shared.installProvider(
                        provider: providerToInstall,
                        selectAfterInstall: selectAfterInstall,
                        preferDeferredRuleSetDownload: true,
                        progress: progressHandler
                    )
                }.value
            }
            await MainActor.run {
                if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                    steps[runningIndex].status = .success
                }
                if let finalizeIndex = steps.firstIndex(where: { $0.id == .finalize }) {
                    steps[finalizeIndex].status = .success
                }
                finished = true
                currentRunningStep = nil
                isRunning = false
            }
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            NSLog("ProviderInstallWizardView(iOS): runInstall success provider=%@ elapsed_ms=%d", provider.id, elapsed)
        } catch {
            await MainActor.run {
                if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                    steps[runningIndex].status = .failure
                    steps[runningIndex].message = error.localizedDescription
                } else if let firstPending = steps.firstIndex(where: { $0.status == .pending }) {
                    steps[firstPending].status = .failure
                    steps[firstPending].message = error.localizedDescription
                }
                errorText = "安装失败：\(error.localizedDescription)"
                currentRunningStep = nil
                isRunning = false
            }
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            NSLog("ProviderInstallWizardView(iOS): runInstall failed provider=%@ elapsed_ms=%d error=%@", provider.id, elapsed, String(describing: error))
        }
    }

    private func symbol(for status: StepState.Status) -> String {
        switch status {
        case .pending: return "○"
        case .running: return "◐"
        case .success: return "●"
        case .failure: return "×"
        }
    }

    private func statusColor(_ status: StepState.Status) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return MarketIOSTheme.meshBlue
        case .success: return MarketIOSTheme.meshMint
        case .failure: return MarketIOSTheme.meshRed
        }
    }

    private var runningHint: String {
        if let running = steps.first(where: { $0.status == .running }) {
            if let msg = running.message, !msg.isEmpty {
                return msg
            }
            return "正在执行：\(running.title)…"
        }
        return "正在运行…"
    }
}
