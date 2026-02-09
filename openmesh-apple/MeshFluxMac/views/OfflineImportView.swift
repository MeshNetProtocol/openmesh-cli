import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VPNLibrary

struct OfflineImportView: View {
    let onInstalled: () -> Void
    let onClose: () -> Void

    @State private var importText: String = ""
    @State private var importURLString: String = ""
    @State private var importProviderID: String = ""
    @State private var importProviderName: String = ""
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("离线导入安装")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("当市场域名需要 VPN 才可访问时，可先导入 JSON/base64 或 URL 内容来创建供应商 profile。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { onClose() }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("provider_id（可选，留空自动生成）", text: $importProviderID)
                    TextField("name（可选）", text: $importProviderName)
                }

                HStack(spacing: 10) {
                    TextField("URL（可选）：https://...", text: $importURLString)
                    Button("从 URL 拉取") {
                        Task { await loadImportFromURL() }
                    }
                    Button("选择文件") {
                        loadImportFromFile()
                    }
                }

                TextEditor(text: $importText)
                    .font(.system(size: 11).monospaced())
                    .frame(minHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                if let importError, !importError.isEmpty {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )

            HStack {
                Spacer()
                Button("安装导入内容") {
                    Task { await installImported() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(minWidth: 680, minHeight: 560)
    }

    private func loadImportFromURL() async {
        importError = nil
        let s = importURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s), u.scheme == "https" else {
            importError = "URL 无效：仅支持 https"
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: u)
            let text = String(data: data, encoding: .utf8) ?? ""
            await MainActor.run {
                importText = text
            }
        } catch {
            importError = "拉取失败：\(error.localizedDescription)"
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

            OfflineImportWindowManager.shared.close()
            ProviderInstallWindowManager.shared.show(
                provider: pseudoProvider,
                installAction: { progress in
                    try await MarketService.shared.installProviderFromImportedConfig(
                        providerID: resolvedID,
                        providerName: resolvedName,
                        packageHash: packageHash,
                        configData: configData,
                        routingRulesData: routingRulesData,
                        ruleSetURLMap: ruleSetURLMap,
                        selectAfterInstall: true,
                        progress: progress
                    )
                },
                onInstallingChange: { isInstalling in
                    if !isInstalling {
                        onInstalled()
                    }
                }
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
}

