import SwiftUI
import VPNLibrary

struct BootstrapFetchWizardIOS: View {
    private enum SourceStatus {
        case waiting
        case searching
        case found
        case failed
    }

    private enum SourceKind: String {
        case github
        case community
        case privateNode
    }

    private struct SourceItem: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let endpoint: String
        let kind: SourceKind
        var status: SourceStatus = .waiting
        var payloadText: String?
        var byteCount: Int?
        var message: String = "等待开始"
        var errorDetail: String?
    }

    private enum FetchResult {
        case success(payload: String, bytes: Int)
        case failure(FetchFailure)
    }

    private struct FetchFailure {
        let brief: String
        let detail: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var progress: Double = 0
    @State private var isSearching = false
    @State private var hasCompletedSearch = false
    @State private var selectedSourceID: UUID?
    @State private var searchTask: Task<Void, Never>?
    @State private var didStartSearch = false
    @State private var installError: String?
    @State private var sources: [SourceItem] = [
        .init(name: "GitHub 公共仓库", detail: "搜索开源配置文件", endpoint: "https://meshnetprotocol.github.io/bootstrap.json", kind: .github),
        .init(name: "开发者社区", detail: "扫描社区共享配置", endpoint: "https://gist.githubusercontent.com/hopwesley/3d3c35ef2dff6f4762f30e1df958f57b/raw/bootstrap.json", kind: .community),
        .init(name: "私人节点", detail: "检查私人节点配置", endpoint: "http://35.247.142.146:7788/api/bootstrap.json", kind: .privateNode),
    ]

    let onImportConfig: () -> Void
    let onInstallConfig: (ImportInstallContext) -> Void

    private var foundCount: Int {
        sources.filter { $0.status == .found }.count
    }

    private var headerDescription: String {
        if hasCompletedSearch {
            if foundCount > 0 {
                return "找到 \(foundCount) 个可用配置来源，选择一个开始安装。"
            }
            return "未找到可用配置来源，可重试搜索或直接导入本地配置。"
        }
        return "正在从多个来源查找可用配置。"
    }

    private var selectedSource: SourceItem? {
        guard let selectedSourceID else { return nil }
        return sources.first(where: { $0.id == selectedSourceID })
    }

    private var hasAvailableSource: Bool {
        foundCount > 0
    }

    var body: some View {
        NavigationView {
            ZStack {
                MarketIOSTheme.windowBackground(scheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        overviewCard

                        if isSearching {
                            progressCard
                        }

                        VStack(spacing: 10) {
                            ForEach(sources) { source in
                                sourceCard(source)
                            }
                        }

                        if hasCompletedSearch {
                            infoCard
                        }

                        if let installError, !installError.isEmpty {
                            errorCard(installError)
                        }
                    }
                    .padding(16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationTitle("配置向导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .tint(MarketIOSTheme.meshBlue)
                }
            }
        }
        .onAppear {
            guard !didStartSearch else { return }
            didStartSearch = true
            startSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var overviewCard: some View {
        MFGlassCard {
            VStack(spacing: 8) {
                Circle()
                    .fill(MarketIOSTheme.meshBlue.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(MarketIOSTheme.meshBlue)
                    }

                VStack(spacing: 2) {
                    Text(hasCompletedSearch ? "选择一个配置来源" : "查找可用配置")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(headerDescription)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 6) {
                    MarketIOSChip(title: "自动搜索", tint: MarketIOSTheme.meshBlue)
                    MarketIOSChip(title: "\(sources.count) 个来源", tint: MarketIOSTheme.meshCyan)
                    if hasCompletedSearch {
                        MarketIOSChip(title: "\(foundCount) 个可用", tint: foundCount > 0 ? MarketIOSTheme.meshMint : MarketIOSTheme.meshAmber)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var progressCard: some View {
        MFGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("搜索进度")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MarketIOSTheme.meshBlue)
                }

                ProgressView(value: progress)
                    .tint(MarketIOSTheme.meshBlue)

                Text("正在检查公开仓库、社区镜像和私人节点。")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sourceCard(_ source: SourceItem) -> some View {
        let selected = selectedSourceID == source.id
        return Button {
            if source.status == .found {
                selectedSourceID = source.id
            }
        } label: {
            MFGlassCard {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconFill(for: source))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: sourceSymbol(for: source))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(iconForeground(for: source))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(source.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        if source.status == .found && !selected {
                            MFStatusBadge(title: "可用", tint: MarketIOSTheme.meshMint)
                        }
                    }

                    Text(source.detail)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(source.message)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(source.status == .failed ? MarketIOSTheme.meshRed : .primary.opacity(0.72))

                    if let errorDetail = source.errorDetail, source.status == .failed {
                        Text(errorDetail)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(MarketIOSTheme.meshRed.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                trailingControl(for: source, selected: selected)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(selected ? MarketIOSTheme.meshBlue.opacity(0.07) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selected ? MarketIOSTheme.meshBlue.opacity(0.32) : MarketIOSTheme.cardStroke(scheme), lineWidth: selected ? 2 : 1)
        )
        }
        .buttonStyle(.plain)
        .disabled(source.status != .found)
        .opacity(source.status == .failed ? 0.82 : 1.0)
    }

    @ViewBuilder
    private func trailingControl(for source: SourceItem, selected: Bool) -> some View {
        switch source.status {
        case .waiting:
            Text("等待中")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        case .searching:
            ProgressView()
                .tint(MarketIOSTheme.meshBlue)
        case .found:
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(selected ? MarketIOSTheme.meshBlue : .secondary.opacity(0.55))
                Text(selected ? "已选择" : "选择")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? MarketIOSTheme.meshBlue : .secondary)
            }
        case .failed:
            Text("失败")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(MarketIOSTheme.meshRed)
        }
    }

    private var infoCard: some View {
        MFGlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MarketIOSTheme.meshBlue)
                    .padding(.top, 2)

                Text("选中一个来源后会直接进入安装流程。也可以跳过搜索，改走本地导入。")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }

    private func errorCard(_ text: String) -> some View {
        MFGlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MarketIOSTheme.meshRed)
                    .padding(.top, 2)

                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MarketIOSTheme.meshRed)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(MarketIOSTheme.meshBlue)
                        .scaleEffect(0.85)
                    Text("正在查找可用配置…")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let selectedSource {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MarketIOSTheme.meshBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedSource.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text("下一步进入安装流程")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                if isSearching {
                    footerSecondaryCapsule(title: "取消搜索", tint: MarketIOSTheme.meshBlue) {
                        cancelSearch()
                    }
                } else {
                    footerSecondaryCapsule(title: "关闭", tint: MarketIOSTheme.meshBlue) {
                        dismiss()
                    }
                    footerSecondaryCapsule(title: "本地导入", tint: MarketIOSTheme.meshCyan) {
                        onImportConfig()
                    }
                }

                Spacer()

                if isSearching {
                    footerPrimaryButton(title: "搜索中…", tint: Color(red: 0.72, green: 0.78, blue: 0.88), isDisabled: true) {}
                        .frame(maxWidth: 210)
                } else if hasAvailableSource {
                    footerPrimaryButton(title: "安装选中配置", tint: MarketIOSTheme.meshBlue, isDisabled: selectedSource == nil) {
                        prepareInstall()
                    }
                    .frame(maxWidth: 210)
                } else {
                    footerPrimaryButton(title: "重试搜索", tint: MarketIOSTheme.meshBlue, isDisabled: false) {
                        startSearch()
                    }
                    .frame(maxWidth: 210)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    private func footerPrimaryButton(title: String, tint: Color, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(.white.opacity(isDisabled ? 0.86 : 1.0))
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.7 : 1.0)
    }

    private func footerSecondaryCapsule(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    private func startSearch() {
        searchTask?.cancel()
        selectedSourceID = nil
        installError = nil
        progress = 0
        isSearching = true
        hasCompletedSearch = false
        sources = sources.map { item in
            var copy = item
            copy.status = .waiting
            copy.payloadText = nil
            copy.byteCount = nil
            copy.message = "等待开始"
            copy.errorDetail = nil
            return copy
        }
        searchTask = Task {
            await searchAllSources()
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        hasCompletedSearch = true
        installError = "已取消配置搜索。你可以导入本地配置，或稍后重新搜索。"
        for index in sources.indices where sources[index].status == .searching {
            sources[index].status = .waiting
            sources[index].message = "已取消"
        }
    }

    private func searchAllSources() async {
        let total = max(1, sources.count)
        await withTaskGroup(of: (UUID, FetchResult).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    let delay = Double(index) * 0.7
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    await MainActor.run {
                        if let currentIndex = sources.firstIndex(where: { $0.id == source.id }) {
                            sources[currentIndex].status = .searching
                            sources[currentIndex].message = "正在下载配置内容..."
                        }
                    }
                    return (source.id, await fetchBootstrap(from: source.endpoint))
                }
            }

            var completed = 0
            for await (id, result) in group {
                completed += 1
                await MainActor.run {
                    if let index = sources.firstIndex(where: { $0.id == id }) {
                        switch result {
                        case .success(let payload, let bytes):
                            sources[index].status = .found
                            sources[index].payloadText = payload
                            sources[index].byteCount = bytes
                            sources[index].message = "下载成功，\(formatByteCount(bytes))"
                            sources[index].errorDetail = nil
                            if selectedSourceID == nil {
                                selectedSourceID = id
                            }
                        case .failure(let failure):
                            sources[index].status = .failed
                            sources[index].message = failure.brief
                            sources[index].errorDetail = failure.detail
                        }
                    }
                    progress = Double(completed) / Double(total)
                }
            }
        }

        await MainActor.run {
            isSearching = false
            hasCompletedSearch = true
            if !hasAvailableSource {
                installError = "所有配置来源当前都不可用。请检查网络后重试，或直接导入本地配置。"
            }
        }
    }

    private func fetchBootstrap(from endpoint: String) async -> FetchResult {
        guard let url = URL(string: endpoint) else {
            return .failure(.init(brief: "地址无效", detail: "URL 格式错误"))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.init(brief: "响应无效", detail: "服务器未返回 HTTP 响应"))
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(.init(brief: "HTTP 错误", detail: "状态码 \(http.statusCode)"))
            }
            guard !data.isEmpty else {
                return .failure(.init(brief: "空响应", detail: "服务器返回了空内容"))
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .failure(.init(brief: "空文本", detail: "返回内容为空白文本"))
            }
            do {
                _ = try parseImportPayload(trimmed)
                return .success(payload: trimmed, bytes: data.count)
            } catch {
                return .failure(.init(brief: "内容格式错误", detail: "不是可安装的 JSON 配置"))
            }
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return .failure(.init(brief: "请求超时", detail: "20 秒内未收到有效响应"))
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .failure(.init(brief: "连接失败", detail: error.localizedDescription))
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return .failure(.init(brief: "TLS 错误", detail: error.localizedDescription))
            default:
                return .failure(.init(brief: "网络错误", detail: error.localizedDescription))
            }
        } catch {
            return .failure(.init(brief: "请求失败", detail: error.localizedDescription))
        }
    }

    private func prepareInstall() {
        installError = nil
        guard let source = selectedSource, let payload = source.payloadText else {
            installError = "请先选择一个可用配置来源。"
            return
        }

        do {
            let (providerID, providerName, packageHash, configData, routingRulesData, ruleSetURLMap) = try parseImportPayload(payload)
            let resolvedID = providerID.isEmpty ? "bootstrap-\(source.kind.rawValue)" : providerID
            let candidateName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let loweredName = candidateName.lowercased()
            let resolvedName: String
            if candidateName.isEmpty || loweredName == "bootstrap" || loweredName == "imported" {
                resolvedName = source.name
            } else {
                resolvedName = candidateName
            }
            let pseudoProvider = TrafficProvider(
                id: resolvedID,
                name: resolvedName,
                description: "引导配置安装",
                config_url: source.endpoint,
                tags: ["Bootstrap"],
                author: "Bootstrap",
                updated_at: "",
                provider_hash: nil,
                package_hash: packageHash.isEmpty ? nil : packageHash,
                price_per_gb_usd: nil,
                detail_url: nil
            )

            onInstallConfig(
                ImportInstallContext(
                pseudoProvider: pseudoProvider,
                resolvedProviderID: resolvedID,
                resolvedProviderName: resolvedName,
                packageHash: packageHash,
                configData: configData,
                routingRulesData: routingRulesData,
                ruleSetURLMap: ruleSetURLMap
            )
            )
        } catch {
            installError = error.localizedDescription
        }
    }

    private func parseImportPayload(_ text: String) throws -> (providerID: String, providerName: String, packageHash: String, configData: Data, routingRulesData: Data?, ruleSetURLMap: [String: String]?) {
        let rawData: Data
        if let decoded = Data(base64Encoded: text), !decoded.isEmpty, (try? JSONSerialization.jsonObject(with: decoded, options: [.fragmentsAllowed])) != nil {
            rawData = decoded
        } else {
            rawData = Data(text.utf8)
        }

        let any = try JSONSerialization.jsonObject(with: rawData, options: [.fragmentsAllowed])
        if let dict = any as? [String: Any],
           let configAny = dict["config"] ?? dict["config_json"] ?? dict["configJSON"] ?? dict["singbox_config"] {
            let providerID = (dict["provider_id"] as? String) ?? (dict["providerID"] as? String) ?? ""
            let providerName = (dict["name"] as? String) ?? ""
            let packageHash = (dict["package_hash"] as? String) ?? (dict["packageHash"] as? String) ?? ""
            let configData = try normalizedJSONData(from: configAny)
            let routingAny = dict["routing_rules"] ?? dict["routing_rules_json"] ?? dict["routingRules"]
            let routingRulesData = try routingAny.map { try normalizedJSONData(from: $0) }
            let ruleSetURLMap: [String: String]?
            if let rsAny = dict["rule_set_urls"] ?? dict["ruleSetURLs"] ?? dict["rule_sets"] {
                ruleSetURLMap = try parseRuleSetURLMap(rsAny)
            } else {
                ruleSetURLMap = nil
            }
            return (providerID, providerName, packageHash, configData, routingRulesData, ruleSetURLMap)
        }

        let configData = try normalizedJSONData(from: any)
        return ("", "", "", configData, nil, nil)
    }

    private func normalizedJSONData(from any: Any) throws -> Data {
        if let stringValue = any as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = Data(trimmed.utf8)
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return data
        }
        return try JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])
    }

    private func parseRuleSetURLMap(_ any: Any) throws -> [String: String] {
        if let dict = any as? [String: Any] {
            var result: [String: String] = [:]
            for (key, value) in dict {
                if let stringValue = value as? String, !stringValue.isEmpty {
                    result[key] = stringValue
                }
            }
            return result
        }
        if let array = any as? [Any] {
            var result: [String: String] = [:]
            for entry in array {
                guard let dict = entry as? [String: Any] else { continue }
                guard let tag = dict["tag"] as? String, !tag.isEmpty else { continue }
                guard let url = dict["url"] as? String, !url.isEmpty else { continue }
                result[tag] = url
            }
            return result
        }
        return [:]
    }

    private func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func sourceSymbol(for source: SourceItem) -> String {
        switch source.status {
        case .waiting:
            switch source.kind {
            case .github:
                return "chevron.left.forwardslash.chevron.right"
            case .community:
                return "person.2.fill"
            case .privateNode:
                return "server.rack"
            }
        case .searching:
            return "arrow.triangle.2.circlepath"
        case .found:
            return "checkmark"
        case .failed:
            return "xmark"
        }
    }

    private func iconFill(for source: SourceItem) -> Color {
        switch source.status {
        case .waiting:
            return Color.black.opacity(0.06)
        case .searching:
            return MarketIOSTheme.meshBlue
        case .found:
            return selectedSourceID == source.id ? MarketIOSTheme.meshBlue : MarketIOSTheme.meshMint
        case .failed:
            return MarketIOSTheme.meshRed.opacity(0.12)
        }
    }

    private func iconForeground(for source: SourceItem) -> Color {
        switch source.status {
        case .waiting:
            return .secondary
        case .searching, .found:
            return .white
        case .failed:
            return MarketIOSTheme.meshRed
        }
    }
}
