import SwiftUI
import VPNLibrary

struct ProviderMarketplaceView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var region: String = "全部"
    @State private var sort: Sort = .updatedDesc

    @State private var allProviders: [TrafficProvider] = []
    @State private var installedPackageHashByProvider: [String: String] = [:]
    @State private var pendingRuleSetsByProvider: [String: [String]] = [:]

    @State private var isLoading = false
    @State private var errorText: String?
    @State private var cacheNotice: String?
    @State private var selectedProviderForInstall: TrafficProvider?
    @State private var hasLoadedInitially = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider().opacity(0.45)
            content
        }
        .navigationTitle("供应商市场")
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
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("搜索（名称/作者/标签/简介）", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await reloadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            HStack(spacing: 10) {
                Picker("地区", selection: $region) {
                    ForEach(regionOptions, id: \.self) { r in
                        Text(r).tag(r)
                    }
                }
                .pickerStyle(.menu)

                Picker("排序", selection: $sort) {
                    Text("更新时间↓").tag(Sort.updatedDesc)
                    Text("价格↑（USD/GB）").tag(Sort.priceAsc)
                    Text("价格↓（USD/GB）").tag(Sort.priceDesc)
                }
                .pickerStyle(.menu)

                Spacer()
            }
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
                if let cacheNotice, !cacheNotice.isEmpty {
                    Text(cacheNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if filteredSortedProviders.isEmpty {
                    Text("没有匹配的供应商")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredSortedProviders) { provider in
                        ProviderMarketRow(
                            provider: provider,
                            localHash: installedPackageHashByProvider[provider.id] ?? "",
                            pendingTags: pendingRuleSetsByProvider[provider.id] ?? [],
                            onInstallOrUpdate: {
                                selectedProviderForInstall = provider
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func reloadAll(reason: String = "manual") async {
        let currentlyLoading = await MainActor.run { isLoading }
        if currentlyLoading {
            NSLog("ProviderMarketplaceView: skip reload because loading is in progress. reason=%@", reason)
            return
        }
        NSLog("ProviderMarketplaceView: reload start. reason=%@", reason)

        let cachedProviders = MarketService.shared.getCachedMarketProviders()
        let localHash = await SharedPreferences.installedProviderPackageHash.get()
        let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
        if !cachedProviders.isEmpty {
            await MainActor.run {
                allProviders = cachedProviders
                installedPackageHashByProvider = localHash
                pendingRuleSetsByProvider = pending
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

            await MainActor.run {
                allProviders = providers
                installedPackageHashByProvider = refreshedLocalHash
                pendingRuleSetsByProvider = refreshedPending
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
}

private enum Sort: String {
    case updatedDesc
    case priceAsc
    case priceDesc
}

private struct ProviderMarketRow: View {
    let provider: TrafficProvider
    let localHash: String
    let pendingTags: [String]
    let onInstallOrUpdate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if isUpdateAvailable {
                        pill("Update", tint: .orange)
                    } else if isInstalled {
                        pill("Installed", tint: .green)
                    }
                    if !pendingTags.isEmpty {
                        pill("Init", tint: .blue)
                    }
                }
                Text(provider.description)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(provider.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let p = provider.price_per_gb_usd {
                        Text(String(format: "%.2f USD/GB", p))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(provider.updated_at)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(actionTitle) { onInstallOrUpdate() }
                .buttonStyle(.borderedProminent)
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

    @Environment(\.dismiss) private var dismiss
    let provider: TrafficProvider
    let installAction: ((_ selectAfterInstall: Bool, _ progress: @escaping @Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)?
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
        self.installAction = installAction
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text(provider.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Toggle("安装完成后切换到该供应商", isOn: $selectAfterInstall)
                    .disabled(isRunning || finished)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(steps) { step in
                            HStack(alignment: .top, spacing: 10) {
                                Text(symbol(for: step.status))
                                    .frame(width: 20, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    if let message = step.message, !message.isEmpty {
                                        Text(message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("关闭") { dismiss() }
                        .disabled(isRunning)
                    Spacer()
                    if finished {
                        Button("完成") {
                            onCompleted()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if isRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(runningHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Button(errorText == nil ? "开始安装" : "重试") {
                            Task { await runInstall() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(16)
            .navigationTitle("安装供应商")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if steps.isEmpty {
                    steps = defaultSteps()
                }
            }
        }
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
            if let installAction {
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
