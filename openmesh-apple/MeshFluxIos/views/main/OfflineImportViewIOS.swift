import SwiftUI
import UniformTypeIdentifiers

struct OfflineImportViewIOS: View {
    @Environment(\.dismiss) private var dismiss

    @State private var importText: String = ""
    @State private var importURLString: String = ""
    @State private var importProviderID: String = ""
    @State private var importProviderName: String = ""
    @State private var importError: String?
    @State private var isFetchingFromURL: Bool = false
    @State private var fetchHint: String = ""
    @State private var showFileImporter = false
    @State private var installContext: ImportInstallContext?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("离线导入安装")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("当市场域名在当前网络不可达时，可通过 JSON/base64 或 URL 内容导入创建供应商 profile。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("provider_id（可选，留空自动生成）", text: $importProviderID)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isFetchingFromURL)
                        TextField("name（可选）", text: $importProviderName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isFetchingFromURL)

                        HStack(spacing: 10) {
                            TextField("URL（可选）：https://...", text: $importURLString)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isFetchingFromURL)
                            Button("从 URL 拉取") {
                                Task { await loadImportFromURL() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isFetchingFromURL)
                        }

                        HStack(spacing: 10) {
                            Button("选择文件") {
                                showFileImporter = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(isFetchingFromURL)
                            Spacer()
                        }

                        TextEditor(text: $importText)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(minHeight: 260)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .disabled(isFetchingFromURL)

                        if let importError, !importError.isEmpty {
                            Text(importError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }

                    HStack {
                        Spacer()
                        Button("安装导入内容") {
                            Task { await installImported() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFetchingFromURL)
                    }
                }
                .padding(16)
            }

            if isFetchingFromURL {
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                    Text(fetchHint.isEmpty ? "正在从 URL 拉取内容，请耐心等待…" : fetchHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .systemBackground))
                )
            }
        }
        .navigationTitle("导入安装")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") { dismiss() }
                    .disabled(isFetchingFromURL)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importError = nil
            do {
                guard let url = try result.get().first else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                importText = text
            } catch {
                importError = "读取文件失败：\(error.localizedDescription)"
            }
        }
        .sheet(item: $installContext) { ctx in
            ProviderInstallWizardView(
                provider: ctx.pseudoProvider,
                installAction: { selectAfterInstall, progress in
                    try await MarketService.shared.installProviderFromImportedConfig(
                        providerID: ctx.resolvedProviderID,
                        providerName: ctx.resolvedProviderName,
                        packageHash: ctx.packageHash,
                        configData: ctx.configData,
                        routingRulesData: ctx.routingRulesData,
                        ruleSetURLMap: ctx.ruleSetURLMap,
                        selectAfterInstall: selectAfterInstall,
                        progress: progress
                    )
                },
                onCompleted: {
                    NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                }
            )
        }
    }

    private func loadImportFromURL() async {
        guard !isFetchingFromURL else { return }
        importError = nil
        await MainActor.run {
            isFetchingFromURL = true
            fetchHint = "正在从 URL 拉取内容，请耐心等待…"
        }
        defer {
            Task { @MainActor in
                isFetchingFromURL = false
                fetchHint = ""
            }
        }

        let rawInput = importURLString
        let s = normalizedURLString(importURLString)
        guard let u = URL(string: s), u.scheme == "https", u.host != nil else {
            importError = "URL 无效：仅支持 https（当前：\(s)）"
            return
        }
        await MainActor.run {
            importURLString = s
        }
        NSLog("OfflineImportViewIOS: fetch raw=%@ normalized=%@ url=%@", rawInput, s, u.absoluteString)
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)

        var lastError: Error?
        for attempt in 1...3 {
            await MainActor.run {
                fetchHint = "正在从 URL 拉取内容（第 \(attempt)/3 次尝试）…"
            }
            do {
                var req = URLRequest(url: u)
                req.timeoutInterval = 20
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
                NSLog("OfflineImportViewIOS: request attempt=%d url=%@", attempt, req.url?.absoluteString ?? "(nil)")
                let (data, _) = try await session.data(for: req)
                let text = String(data: data, encoding: .utf8) ?? ""
                await MainActor.run {
                    importText = text
                }
                return
            } catch {
                lastError = error
                let ns = error as NSError
                let failingURLString = (ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? ""
                let failingURL = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString ?? ""
                NSLog(
                    "OfflineImportViewIOS: URLSession failed attempt=%d url=%@ code=%d domain=%@ failingURLString=%@ failingURL=%@ error=%@",
                    attempt,
                    u.absoluteString,
                    ns.code,
                    ns.domain,
                    failingURLString,
                    failingURL,
                    String(describing: error)
                )
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(300_000_000 * attempt))
                }
            }
        }

        if let lastError {
            if shouldFallbackToWebView(lastError) {
                do {
                    await MainActor.run {
                        fetchHint = "正在使用兼容模式拉取（WebView）…"
                    }
                    NSLog("OfflineImportViewIOS: trying WebView fallback url=%@", u.absoluteString)
                    let text = try await WebViewTextFetcher().fetchText(url: u, timeoutSeconds: 20)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                        await MainActor.run {
                            importText = trimmed
                        }
                        return
                    }
                    importError = "拉取失败：WebView 返回内容不是 JSON\nURL：\(s)"
                } catch {
                    importError = "拉取失败：\(error.localizedDescription)\nURL：\(s)\n\n提示：当前网络可能在 TLS 握手阶段重置连接。"
                }
            } else {
                importError = "拉取失败：\(lastError.localizedDescription)\nURL：\(s)"
            }
        }
    }

    private func installImported() async {
        importError = nil
        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            importError = "请输入导入内容"
            return
        }

        do {
            let (providerID, providerName, packageHash, configData, routingRulesData, ruleSetURLMap) = try parseImportPayload(trimmed)
            let resolvedID = !importProviderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? importProviderID : providerID
            let resolvedName = !importProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? importProviderName : providerName

            let pseudoProvider = TrafficProvider(
                id: resolvedID.isEmpty ? "imported" : resolvedID,
                name: resolvedName.isEmpty ? "导入供应商" : resolvedName,
                description: "离线导入安装",
                config_url: "",
                tags: ["Import"],
                author: "Local",
                updated_at: "",
                provider_hash: nil,
                package_hash: packageHash.isEmpty ? nil : packageHash,
                price_per_gb_usd: nil,
                detail_url: nil
            )

            installContext = ImportInstallContext(
                pseudoProvider: pseudoProvider,
                resolvedProviderID: resolvedID,
                resolvedProviderName: resolvedName,
                packageHash: packageHash,
                configData: configData,
                routingRulesData: routingRulesData,
                ruleSetURLMap: ruleSetURLMap
            )
        } catch {
            importError = error.localizedDescription
        }
    }

    private func parseImportPayload(_ text: String) throws -> (providerID: String, providerName: String, packageHash: String, configData: Data, routingRulesData: Data?, ruleSetURLMap: [String: String]?) {
        let rawData: Data
        if let b64 = Data(base64Encoded: text), !b64.isEmpty, (try? JSONSerialization.jsonObject(with: b64, options: [.fragmentsAllowed])) != nil {
            rawData = b64
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
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = Data(trimmed.utf8)
            _ = try JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
            return d
        }
        return try JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])
    }

    private func parseRuleSetURLMap(_ any: Any) throws -> [String: String] {
        if let dict = any as? [String: Any] {
            var result: [String: String] = [:]
            for (k, v) in dict {
                if let s = v as? String, !s.isEmpty {
                    result[k] = s
                }
            }
            return result
        }
        if let arr = any as? [Any] {
            var result: [String: String] = [:]
            for e in arr {
                guard let d = e as? [String: Any] else { continue }
                guard let tag = d["tag"] as? String, !tag.isEmpty else { continue }
                guard let url = d["url"] as? String, !url.isEmpty else { continue }
                result[tag] = url
            }
            return result
        }
        return [:]
    }

    private func shouldFallbackToWebView(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorSecureConnectionFailed || ns.code == NSURLErrorCannotConnectToHost {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == kCFErrorDomainCFNetwork as String {
            if underlying.code == NSURLErrorSecureConnectionFailed {
                return true
            }
        }
        return false
    }

    private func normalizedURLString(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("`") && s.hasSuffix("`")) || (s.hasPrefix("\"") && s.hasSuffix("\"")) {
            s = String(s.dropFirst().dropLast())
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ",，。;；"))
        return s
    }
}

private struct ImportInstallContext: Identifiable {
    let id = UUID()
    let pseudoProvider: TrafficProvider
    let resolvedProviderID: String
    let resolvedProviderName: String
    let packageHash: String
    let configData: Data
    let routingRulesData: Data?
    let ruleSetURLMap: [String: String]?
}
