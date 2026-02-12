import SwiftUI
import UIKit

struct OfflineImportViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var importText: String = ""
    @State private var importURLString: String = ""
    @State private var importProviderID: String = ""
    @State private var importProviderName: String = ""
    @State private var importError: String?
    @State private var isFetchingFromURL: Bool = false
    @State private var fetchHint: String = ""
    @State private var installContext: ImportInstallContext?
    @FocusState private var focusedField: FocusField?

    var body: some View {
        ZStack {
            MarketIOSTheme.windowBackground(scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    importOverviewCard

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("provider_id（可选，留空自动生成）", text: $importProviderID)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isFetchingFromURL)
                            .focused($focusedField, equals: .providerID)
                        TextField("name（可选）", text: $importProviderName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isFetchingFromURL)
                            .focused($focusedField, equals: .providerName)

                        HStack(spacing: 10) {
                            TextField("URL（可选）：http:// 或 https://", text: $importURLString)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isFetchingFromURL)
                                .focused($focusedField, equals: .url)
                            Button("从 URL 拉取") {
                                dismissKeyboard()
                                Task { await loadImportFromURL() }
                            }
                            .buttonStyle(.bordered)
                            .tint(MarketIOSTheme.meshBlue)
                            .disabled(isFetchingFromURL)
                        }

                        HStack(spacing: 8) {
                            Button("粘贴剪贴板") {
                                pasteFromClipboard()
                            }
                            .buttonStyle(.bordered)
                            .tint(MarketIOSTheme.meshCyan)
                            .disabled(isFetchingFromURL)

                            Button("清空内容") {
                                clearImportContent()
                            }
                            .buttonStyle(.bordered)
                            .tint(MarketIOSTheme.meshAmber)
                            .disabled(isFetchingFromURL || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer(minLength: 0)

                            Text("行 \(importLineCount)  字符 \(importText.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $importText)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(minHeight: 260, maxHeight: 380)
                            .padding(6)
                            .focused($focusedField, equals: .content)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(MarketIOSTheme.cardFill(scheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                            )
                            .disabled(isFetchingFromURL)

                        if let importError, !importError.isEmpty {
                            Text(importError)
                                .font(.caption)
                                .foregroundStyle(MarketIOSTheme.meshRed)
                                .textSelection(.enabled)
                        }
                    }
                    .marketIOSCard(horizontal: 12, vertical: 12)
                }
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }
            }

            if isFetchingFromURL {
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(MarketIOSTheme.meshBlue)
                    Text(fetchHint.isEmpty ? "正在从 URL 拉取内容，请耐心等待…" : fetchHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(MarketIOSTheme.cardFill(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            installFooter
        }
        .navigationTitle("导入安装")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") { dismiss() }
                    .tint(MarketIOSTheme.meshBlue)
                    .disabled(isFetchingFromURL)
            }
        }
        .sheet(item: $installContext) { ctx in
            ImportedInstallWizardView(
                provider: ctx.pseudoProvider,
                context: ctx,
                onCompleted: {
                    NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                }
            )
        }
    }

    private var importOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("离线导入安装")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("当市场域名在当前网络不可达时，可通过 JSON/base64 或 URL 内容导入创建供应商 profile。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                MarketIOSChip(title: "JSON/Base64", tint: MarketIOSTheme.meshBlue)
                MarketIOSChip(title: "URL 拉取", tint: MarketIOSTheme.meshCyan)
                MarketIOSChip(title: "本地导入", tint: MarketIOSTheme.meshAmber)
                Spacer(minLength: 0)
            }
        }
        .marketIOSCard(horizontal: 12, vertical: 12)
    }

    private var installFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "等待输入内容" : "准备安装导入内容")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("行 \(importLineCount) · 字符 \(importText.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("安装导入内容") {
                dismissKeyboard()
                Task { await installImported() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MarketIOSTheme.meshBlue)
            .disabled(isFetchingFromURL || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var importLineCount: Int {
        let trimmed = importText.trimmingCharacters(in: .newlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.split(whereSeparator: \.isNewline).count
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
        dismissKeyboard()

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
        dismissKeyboard()
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

    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            importText = text
        }
        dismissKeyboard()
    }

    private func clearImportContent() {
        importText = ""
        importError = nil
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

private enum FocusField {
    case providerID
    case providerName
    case url
    case content
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

private struct ImportedInstallWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let provider: TrafficProvider
    let context: ImportInstallContext
    let onCompleted: () -> Void

    @State private var steps: [ProviderInstallWizardView.StepState] = []
    @State private var isRunning = false
    @State private var selectAfterInstall = true
    @State private var errorText: String?
    @State private var finished = false
    @State private var currentRunningStep: MarketService.InstallStep?

    var body: some View {
        NavigationView {
            ZStack {
                MarketIOSTheme.windowBackground(scheme)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text(provider.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Toggle("安装完成后切换到该供应商", isOn: $selectAfterInstall)
                        .tint(MarketIOSTheme.meshBlue)
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
                    .marketIOSCard(horizontal: 12, vertical: 10)
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
        HStack {
            Button("关闭") { dismiss() }
                .tint(MarketIOSTheme.meshBlue)
                .disabled(isRunning)
            Spacer()
            if finished {
                Button("完成") {
                    onCompleted()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(MarketIOSTheme.meshBlue)
            } else if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(MarketIOSTheme.meshBlue)
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
                .tint(MarketIOSTheme.meshBlue)
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

    private func defaultSteps() -> [ProviderInstallWizardView.StepState] {
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
        NSLog("OfflineImportViewIOS: runInstall start provider=%@", context.resolvedProviderID)
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
            let providerID = context.resolvedProviderID
            let providerName = context.resolvedProviderName
            let packageHash = context.packageHash
            let configData = context.configData
            let routingRulesData = context.routingRulesData
            let ruleSetURLMap = context.ruleSetURLMap
            try await Task.detached(priority: .userInitiated) {
                try await MarketService.shared.installProviderFromImportedConfig(
                    providerID: providerID,
                    providerName: providerName,
                    packageHash: packageHash,
                    configData: configData,
                    routingRulesData: routingRulesData,
                    ruleSetURLMap: ruleSetURLMap,
                    selectAfterInstall: selectAfterInstall,
                    preferDeferredRuleSetDownload: true,
                    progress: progressHandler
                )
            }.value
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
            NSLog("OfflineImportViewIOS: runInstall success provider=%@ elapsed_ms=%d", context.resolvedProviderID, elapsed)
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
            NSLog("OfflineImportViewIOS: runInstall failed provider=%@ elapsed_ms=%d error=%@", context.resolvedProviderID, elapsed, String(describing: error))
        }
    }

    private func symbol(for status: ProviderInstallWizardView.StepState.Status) -> String {
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
