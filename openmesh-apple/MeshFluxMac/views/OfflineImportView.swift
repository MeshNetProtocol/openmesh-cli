import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VPNLibrary
import WebKit

struct OfflineImportView: View {
    let onInstalled: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    @State private var importText: String = ""
    @State private var importURLString: String = ""
    @State private var importError: String?
    @State private var isFetchingFromURL: Bool = false
    @State private var fetchHint: String = ""
    @State private var selectedFileName: String?

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 12) {
                headerSection

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        formSection
                        if let importError, !importError.isEmpty {
                            errorSection(importError)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider().overlay(MeshFluxTheme.meshBlue.opacity(0.16))
                actionSection
            }
            .padding(16)

            if isFetchingFromURL {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(MeshFluxTheme.meshBlue)
                    Text(fetchHint.isEmpty ? "正在从 URL 拉取内容，请耐心等待…" : fetchHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MeshFluxTheme.cardFill(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
                )
            }
        }
        .frame(minWidth: 740, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("离线导入安装")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.72))
                Text("从本地内容创建供应商")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("当市场域名需要 VPN 才可访问时，可先导入 JSON/base64 或 URL 内容来创建供应商 profile。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    importBadge(title: "粘贴 JSON", tint: MeshFluxTheme.meshBlue)
                    importBadge(title: "支持 URL", tint: MeshFluxTheme.meshCyan)
                    importBadge(title: "本地文件", tint: MeshFluxTheme.meshMint)
                }
            }

            Spacer(minLength: 12)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.34, green: 0.39, blue: 0.45))
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.66))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isFetchingFromURL)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MeshFluxTheme.meshBlue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("导入来源")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("你可以直接粘贴 JSON/base64，也可以先从 URL 拉取内容，或者从本地选择配置文件。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    if importURLString.isEmpty {
                        Text("URL（可选）：http:// 或 https://")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                    }
                    TextField("", text: $importURLString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .disabled(isFetchingFromURL)
                }
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.58))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                        }
                }

                Button("从 URL 拉取") {
                    Task { await loadImportFromURL() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshBlue)
                .disabled(isFetchingFromURL)

                Button("选择文件") {
                    loadImportFromFile()
                }
                .buttonStyle(.bordered)
                .disabled(isFetchingFromURL)
            }

            HStack(spacing: 8) {
                importSourcePill(
                    title: selectedFileName ?? "尚未选择本地文件",
                    tint: selectedFileName == nil ? Color.gray : MeshFluxTheme.meshMint
                )
                Spacer()
                Text(importText.isEmpty ? "等待导入内容" : "已载入 \(importText.count) 个字符")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("导入内容")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    Text("支持 JSON / base64")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $importText)
                        .font(.system(size: 12).monospaced())
                        .frame(minHeight: 380)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .disabled(isFetchingFromURL)

                    if importText.isEmpty {
                        Text("""
粘贴供应商 JSON、base64 内容，或先从 URL / 本地文件导入。

推荐格式：
- { "config": { ... } }
- 完整 config.json
- Base64 编码后的 JSON 内容
""")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.82))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MeshFluxTheme.meshBlue.opacity(0.18), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private func errorSection(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))
            Text(text)
                .font(.caption)
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.88, green: 0.30, blue: 0.36).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.88, green: 0.30, blue: 0.36).opacity(0.32), lineWidth: 1)
        )
    }

    private var actionSection: some View {
        HStack {
            Button("清空") {
                importText = ""
                importURLString = ""
                selectedFileName = nil
            }
            .buttonStyle(.bordered)
            .disabled(isFetchingFromURL)

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("导入后将创建供应商 profile，并进入安装流程")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("安装导入内容") {
                    Task { await installImported() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshBlue)
                .disabled(isFetchingFromURL)
            }
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
        let scheme = URL(string: s)?.scheme?.lowercased()
        guard let u = URL(string: s), (scheme == "https" || scheme == "http"), u.host != nil else {
            importError = "URL 无效：仅支持 http/https（当前：\(s)）"
            return
        }
        await MainActor.run {
            importURLString = s
        }
        NSLog("OfflineImportView: fetch raw=%@ normalized=%@ url=%@", rawInput, s, u.absoluteString)
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
                NSLog("OfflineImportView: request attempt=%d url=%@", attempt, req.url?.absoluteString ?? "(nil)")
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
                    "OfflineImportView: URLSession failed attempt=%d url=%@ code=%d domain=%@ failingURLString=%@ failingURL=%@ error=%@",
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
                    NSLog("OfflineImportView: trying WebView fallback url=%@", u.absoluteString)
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
                    importError = "拉取失败：\(error.localizedDescription)\nURL：\(s)\n\n提示：当前网络可能会对 GitHub Pages 的非浏览器 TLS 连接进行重置；已尝试 WebView 兼容模式仍失败。"
                }
            } else {
                importError = "拉取失败：\(lastError.localizedDescription)\nURL：\(s)"
            }
        }
    }

    private func loadImportFromFile() {
        importError = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            let text = (try? String(contentsOf: url)) ?? ""
            importText = text
            selectedFileName = url.lastPathComponent
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
            NSLog("OfflineImportView: installImported begin payload_chars=%ld", trimmed.count)
            let (providerID, providerName, packageHash, configData, routingRulesData, ruleSetURLMap) = try parseImportPayload(trimmed)
            let resolvedID = providerID.isEmpty ? "imported" : providerID
            let resolvedName = providerName.isEmpty ? "导入供应商" : providerName

            let pseudoProvider = TrafficProvider(
                id: resolvedID,
                name: resolvedName,
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

            NSLog(
                "OfflineImportView: open install wizard provider_id=%@ name=%@ package_hash=%@ config_bytes=%ld routing_rules_bytes=%ld rule_set_count=%ld",
                resolvedID,
                resolvedName,
                packageHash,
                configData.count,
                routingRulesData?.count ?? 0,
                ruleSetURLMap?.count ?? 0
            )
            OfflineImportWindowManager.shared.close()
            DispatchQueue.main.async {
                ProviderInstallWindowManager.shared.show(
                    provider: pseudoProvider,
                    installAction: { selectAfterInstall, progress in
                        try await MarketService.shared.installProviderFromImportedConfig(
                            providerID: resolvedID,
                            providerName: resolvedName,
                            packageHash: packageHash,
                            configData: configData,
                            routingRulesData: routingRulesData,
                            ruleSetURLMap: ruleSetURLMap,
                            selectAfterInstall: selectAfterInstall,
                            progress: progress
                        )
                    },
                    onInstallingChange: { isInstalling in
                        if !isInstalling {
                            onInstalled()
                        }
                    }
                )
            }
        } catch {
            NSLog("OfflineImportView: installImported failed error=%@", String(describing: error))
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

    private func importBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            }
    }

    private func importSourcePill(title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint.opacity(0.7))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint == Color.gray ? Color.secondary : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill((tint == Color.gray ? Color.gray : tint).opacity(0.10))
        }
    }
}
