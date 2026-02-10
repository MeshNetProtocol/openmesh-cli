import Foundation
import VPNLibrary

public struct TrafficProvider: Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let config_url: String
    public let tags: [String]
    public let author: String
    public let updated_at: String
    public let provider_hash: String?
    public let package_hash: String?
    public let price_per_gb_usd: Double?
    public let detail_url: String?
}

struct MarketResponse: Codable {
    let ok: Bool
    let data: [TrafficProvider]?
    let error: String?
}

struct MarketManifestResponse: Codable {
    let ok: Bool
    let market_version: Int?
    let updated_at: String?
    let providers: [TrafficProvider]?
    let error: String?
}

struct ProviderDetailResponse: Codable {
    let ok: Bool
    let provider: TrafficProvider?
    let package: ProviderPackage?
    let error: String?
    let error_code: String?
    let details: [String]?
}

struct ProviderPackage: Codable {
    let package_hash: String
    let files: [ProviderPackageFile]
}

struct ProviderPackageFile: Codable {
    let type: String
    let url: String?
    let tag: String?
    let mode: String?
}

public class MarketService {
    public static let shared = MarketService()
    
    private let baseURLs = [
        "https://openmesh-api.ribencong.workers.dev/api/v1"
        // "http://localhost:8787/api/v1"
    ]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private func fetchData(_ url: URL, timeout: TimeInterval = 15) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let (data, _) = try await session.data(for: req)
        return data
    }

    private func fetchDataWithResponse(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, res) = try await session.data(for: req)
        guard let http = res as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func firstSuccessful<T>(_ op: (String) async throws -> T) async throws -> T {
        var lastError: Error?
        for base in baseURLs {
            do {
                return try await op(base)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private var marketManifestCacheFileURL: URL {
        FilePath.meshFluxSharedDataDirectory
            .appendingPathComponent("market_manifest.json", isDirectory: false)
    }

    private var marketRecommendedCacheFileURL: URL {
        FilePath.meshFluxSharedDataDirectory
            .appendingPathComponent("market_recommended.json", isDirectory: false)
    }

    private func readCachedMarketProviders() -> [TrafficProvider]? {
        guard let data = try? Data(contentsOf: marketManifestCacheFileURL), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([TrafficProvider].self, from: data)
    }

    private func writeCachedMarketProviders(_ providers: [TrafficProvider]) throws {
        let fm = FileManager.default
        let dir = marketManifestCacheFileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(providers)
        let tmp = dir.appendingPathComponent(".market_manifest.\(UUID().uuidString).tmp", isDirectory: false)
        try data.write(to: tmp, options: [.atomic])
        if fm.fileExists(atPath: marketManifestCacheFileURL.path) {
            try? fm.removeItem(at: marketManifestCacheFileURL)
        }
        try fm.moveItem(at: tmp, to: marketManifestCacheFileURL)
    }

    private func readCachedRecommendedProviders() -> [TrafficProvider]? {
        guard let data = try? Data(contentsOf: marketRecommendedCacheFileURL), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([TrafficProvider].self, from: data)
    }

    private func writeCachedRecommendedProviders(_ providers: [TrafficProvider]) throws {
        let fm = FileManager.default
        let dir = marketRecommendedCacheFileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(providers)
        let tmp = dir.appendingPathComponent(".market_recommended.\(UUID().uuidString).tmp", isDirectory: false)
        try data.write(to: tmp, options: [.atomic])
        if fm.fileExists(atPath: marketRecommendedCacheFileURL.path) {
            try? fm.removeItem(at: marketRecommendedCacheFileURL)
        }
        try fm.moveItem(at: tmp, to: marketRecommendedCacheFileURL)
    }

    private func providerProfileID(providerID: String) async -> Int64? {
        let profileToProvider = await SharedPreferences.installedProviderIDByProfile.get()
        for (profileIDString, pid) in profileToProvider where pid == providerID {
            if let id = Int64(profileIDString) { return id }
        }
        return nil
    }

    public enum InstallStep: String, CaseIterable, Identifiable {
        case fetchDetail
        case downloadConfig
        case validateConfig
        case writeConfig
        case downloadRoutingRules
        case writeRoutingRules
        case downloadRuleSet
        case writeRuleSet
        case registerProfile
        case finalize

        public var id: String { rawValue }
    }

    public struct InstallProgress: Sendable {
        public let step: InstallStep
        public let message: String

        public init(step: InstallStep, message: String) {
            self.step = step
            self.message = message
        }
    }
    
    public func fetchProviders() async throws -> [TrafficProvider] {
        try await firstSuccessful { base in
            guard let url = URL(string: "\(base)/providers") else {
                throw URLError(.badURL)
            }
            let data = try await fetchData(url, timeout: 30)
            let response = try JSONDecoder().decode(MarketResponse.self, from: data)
            if let providers = response.data {
                return providers
            }
            throw NSError(domain: "MarketService", code: 1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
        }
    }

    public func fetchMarketProvidersCached() async throws -> [TrafficProvider] {
        do {
            return try await firstSuccessful { base in
                guard let url = URL(string: "\(base)/market/manifest") else {
                    throw URLError(.badURL)
                }
                var req = URLRequest(url: url)
                req.timeoutInterval = 30
                let etag = await SharedPreferences.marketManifestETag.get()
                if !etag.isEmpty {
                    req.setValue(etag, forHTTPHeaderField: "If-None-Match")
                }
                let (data, http) = try await fetchDataWithResponse(req)
                if http.statusCode == 304 {
                    if let cached = readCachedMarketProviders() {
                        return cached
                    }
                    return try await fetchProviders()
                }
                guard http.statusCode >= 200 && http.statusCode < 300 else {
                    return try await fetchProviders()
                }
                let response = try JSONDecoder().decode(MarketManifestResponse.self, from: data)
                guard response.ok, let providers = response.providers else {
                    return try await fetchProviders()
                }
                if let updatedAt = response.updated_at {
                    await SharedPreferences.marketManifestUpdatedAt.set(updatedAt)
                }
                if let newETag = http.value(forHTTPHeaderField: "ETag"), !newETag.isEmpty {
                    await SharedPreferences.marketManifestETag.set(newETag)
                }
                try writeCachedMarketProviders(providers)
                return providers
            }
        } catch {
            if let cached = readCachedMarketProviders() {
                return cached
            }
            throw error
        }
    }

    public func fetchMarketRecommendedCached() async throws -> [TrafficProvider] {
        do {
            return try await firstSuccessful { base in
                guard let url = URL(string: "\(base)/market/recommended") else {
                    throw URLError(.badURL)
                }
                let data = try await fetchData(url, timeout: 20)
                let response = try JSONDecoder().decode(MarketResponse.self, from: data)
                guard response.ok, let providers = response.data else {
                    throw NSError(domain: "MarketService", code: 11, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
                }
                try writeCachedRecommendedProviders(providers)
                return providers
            }
        } catch {
            if let cached = readCachedRecommendedProviders() {
                return cached
            }
            throw error
        }
    }

    public func uninstallProvider(providerID: String, vpnConnected: Bool) async throws {
        try await ProviderUninstaller.uninstall(providerID: providerID, vpnConnected: vpnConnected, progress: nil)
        await MainActor.run {
            NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
        }
    }
    
    func fetchProviderDetail(providerID: String, fallbackDetailURL: String? = nil) async throws -> ProviderDetailResponse {
        if let fallbackDetailURL, let url = URL(string: fallbackDetailURL) {
            let data = try await fetchData(url, timeout: 30)
            let response = try JSONDecoder().decode(ProviderDetailResponse.self, from: data)
            guard response.ok else {
                var msg = response.error ?? "Unknown error"
                if let code = response.error_code, !code.isEmpty {
                    msg = "[\(code)] \(msg)"
                }
                if let details = response.details, !details.isEmpty {
                    msg += "\n" + details.joined(separator: "\n")
                }
                throw NSError(domain: "MarketService", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            return response
        }

        return try await firstSuccessful { base in
            let urlString = "\(base)/providers/\(providerID)"
            guard let url = URL(string: urlString) else {
                throw URLError(.badURL)
            }
            let data = try await fetchData(url, timeout: 30)
            let response = try JSONDecoder().decode(ProviderDetailResponse.self, from: data)
            guard response.ok else {
                var msg = response.error ?? "Unknown error"
                if let code = response.error_code, !code.isEmpty {
                    msg = "[\(code)] \(msg)"
                }
                if let details = response.details, !details.isEmpty {
                    msg += "\n" + details.joined(separator: "\n")
                }
                throw NSError(domain: "MarketService", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            return response
        }
    }

    private func patchConfigRuleSetsToLocalPaths(configData: Data, providerID: String, downloadedRuleSetTags: Set<String>) throws -> Data {
        guard !downloadedRuleSetTags.isEmpty else { return configData }
        let obj = try JSONSerialization.jsonObject(with: configData, options: [.fragmentsAllowed])
        guard var config = obj as? [String: Any] else { return configData }
        guard var route = config["route"] as? [String: Any] else { return configData }
        guard var ruleSets = route["rule_set"] as? [Any] else { return configData }

        let providerRuleSetDir = FilePath.providerRuleSetDirectory(providerID: providerID)
        var changed = false
        for i in ruleSets.indices {
            guard var rs = ruleSets[i] as? [String: Any] else { continue }
            guard (rs["type"] as? String) == "remote" else { continue }
            guard let tag = rs["tag"] as? String, downloadedRuleSetTags.contains(tag) else { continue }
            let localPath = providerRuleSetDir.appendingPathComponent("\(tag).srs", isDirectory: false).path
            rs = [
                "type": "local",
                "tag": tag,
                "format": "binary",
                "path": localPath,
            ]
            ruleSets[i] = rs
            changed = true
        }
        if changed {
            route["rule_set"] = ruleSets
            config["route"] = route
            return try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        }
        return configData
    }

    private func makeBootstrapConfigData(fullConfigData: Data, removingRemoteRuleSets: Bool) throws -> (data: Data, removedRuleSetTags: Set<String>) {
        let obj = try JSONSerialization.jsonObject(with: fullConfigData, options: [.fragmentsAllowed])
        guard var config = obj as? [String: Any] else { return (fullConfigData, []) }

        var removedTags: Set<String> = []

        if var route = config["route"] as? [String: Any] {
            if removingRemoteRuleSets, let ruleSets = route["rule_set"] as? [Any] {
                var kept: [Any] = []
                for any in ruleSets {
                    guard let rs = any as? [String: Any] else { continue }
                    let type = (rs["type"] as? String) ?? ""
                    if type == "remote" {
                        if let tag = rs["tag"] as? String, !tag.isEmpty {
                            removedTags.insert(tag)
                        }
                        continue
                    }
                    kept.append(rs)
                }
                route["rule_set"] = kept.isEmpty ? nil : kept
            }

            if let rulesAny = route["rules"] as? [Any] {
                var keptRules: [Any] = []
                for any in rulesAny {
                    guard let rule = any as? [String: Any] else { continue }
                    let ref = rule["rule_set"]
                    if let s = ref as? String, removedTags.contains(s) { continue }
                    if let arr = ref as? [String], arr.contains(where: { removedTags.contains($0) }) { continue }
                    keptRules.append(rule)
                }
                route["rules"] = keptRules
            }

            route["final"] = "proxy"
            config["route"] = route
        }

        if var dns = config["dns"] as? [String: Any] {
            if let rulesAny = dns["rules"] as? [Any] {
                var keptRules: [Any] = []
                for any in rulesAny {
                    guard let rule = any as? [String: Any] else { continue }
                    let ref = rule["rule_set"]
                    if let s = ref as? String, removedTags.contains(s) { continue }
                    if let arr = ref as? [String], arr.contains(where: { removedTags.contains($0) }) { continue }
                    keptRules.append(rule)
                }
                dns["rules"] = keptRules
                config["dns"] = dns
            }
        }

        if var inbounds = config["inbounds"] as? [[String: Any]], !removedTags.isEmpty {
            for i in inbounds.indices {
                if var exclude = inbounds[i]["route_exclude_address_set"] as? [String] {
                    exclude.removeAll(where: { removedTags.contains($0) })
                    inbounds[i]["route_exclude_address_set"] = exclude.isEmpty ? nil : exclude
                }
            }
            config["inbounds"] = inbounds
        }

        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return (data, removedTags)
    }

    private func validateTunStackCompatibilityForInstall(_ configData: Data) throws {
        guard let obj = (try? JSONSerialization.jsonObject(with: configData, options: [.fragmentsAllowed])) as? [String: Any] else {
            return
        }
        guard let inboundsAny = obj["inbounds"] as? [Any] else { return }
        for any in inboundsAny {
            guard let inbound = any as? [String: Any] else { continue }
            guard (inbound["type"] as? String) == "tun" else { continue }
            let stack = (inbound["stack"] as? String)?.lowercased()
            if stack == "system" || stack == "mixed" {
                throw NSError(domain: "com.meshflux.market", code: 1001, userInfo: [
                    NSLocalizedDescriptionKey: "该供应商配置不兼容当前系统设置：tun.stack 不能是 system/mixed（includeAllNetworks 已启用）。请联系供应商将 stack 改为 gvisor 或移除 stack 字段。",
                ])
            }
        }
    }

    public func installProvider(
        provider: TrafficProvider,
        selectAfterInstall: Bool,
        progress: @Sendable (InstallProgress) -> Void
    ) async throws {
        let fm = FileManager.default
        progress(.init(step: .fetchDetail, message: "读取供应商详情"))
        let detail = try await fetchProviderDetail(providerID: provider.id, fallbackDetailURL: provider.detail_url)
        let packageHashForUI = detail.package?.package_hash ?? provider.package_hash ?? ""
        let fileTypes = (detail.package?.files ?? []).map { $0.type }.joined(separator: ", ")
        if !packageHashForUI.isEmpty || !fileTypes.isEmpty {
            let parts = [
                packageHashForUI.isEmpty ? nil : "package_hash=\(packageHashForUI)",
                fileTypes.isEmpty ? nil : "files=\(fileTypes)",
            ].compactMap { $0 }
            progress(.init(step: .fetchDetail, message: "读取供应商详情：\(parts.joined(separator: "；"))"))
        }

        let packageHash = detail.package?.package_hash ?? provider.package_hash ?? ""
        let packageFiles = detail.package?.files ?? []
        let providerID = provider.id

        let providerDir = FilePath.providerDirectory(providerID: providerID)
        let providersRoot = providerDir.deletingLastPathComponent()
        let stagingRoot = providersRoot.appendingPathComponent(".staging", isDirectory: true)
        let backupRoot = providersRoot.appendingPathComponent(".backup", isDirectory: true)
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true, attributes: nil)

        let stagingDir = stagingRoot.appendingPathComponent("\(providerID)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: nil)

        let configURLString = packageFiles.first(where: { $0.type == "config" })?.url ?? provider.config_url
        guard let configEndpointURL = URL(string: configURLString) else { throw URLError(.badURL) }

        do {
            progress(.init(step: .downloadConfig, message: "下载配置文件：\(configEndpointURL.absoluteString)"))
            let downloadedConfigData = try await fetchData(configEndpointURL, timeout: 20)
            guard !downloadedConfigData.isEmpty else {
                throw NSError(domain: "MarketService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty config content"])
            }

            progress(.init(step: .validateConfig, message: "解析配置文件"))
            let configData = downloadedConfigData
            _ = try JSONSerialization.jsonObject(with: configData, options: [.fragmentsAllowed])
            try validateTunStackCompatibilityForInstall(configData)

            let rulesURLString = packageFiles.first(where: { $0.type == "force_proxy" })?.url
            if let rulesURLString, let rulesURL = URL(string: rulesURLString) {
                progress(.init(step: .downloadRoutingRules, message: "下载 routing_rules.json：\(rulesURL.absoluteString)"))
                let rulesData = try await fetchData(rulesURL, timeout: 20)
                progress(.init(step: .writeRoutingRules, message: "写入 routing_rules.json"))
                let stagingRulesURL = stagingDir.appendingPathComponent("routing_rules.json", isDirectory: false)
                try rulesData.write(to: stagingRulesURL, options: [.atomic])
            } else {
                progress(.init(step: .downloadRoutingRules, message: "跳过：该供应商未提供 routing_rules.json"))
            }

            let ruleSetFiles = packageFiles.filter { $0.type == "rule_set" }
            var downloadedTags: Set<String> = []
            var pendingTags: Set<String> = []
            var ruleSetURLMap: [String: String] = [:]
            if ruleSetFiles.isEmpty {
                progress(.init(step: .downloadRuleSet, message: "跳过：该供应商未提供 rule-set 文件"))
            } else {
                let stagingRuleSetDir = stagingDir.appendingPathComponent("rule-set", isDirectory: true)
                try fm.createDirectory(at: stagingRuleSetDir, withIntermediateDirectories: true, attributes: nil)
                for f in ruleSetFiles {
                    guard let tag = f.tag, !tag.isEmpty, let urlString = f.url, let u = URL(string: urlString) else { continue }
                    ruleSetURLMap[tag] = urlString
                    progress(.init(step: .downloadRuleSet, message: "下载 rule-set(\(tag))：\(u.absoluteString)"))
                    do {
                        let data = try await fetchData(u, timeout: 20)
                        if data.isEmpty {
                            pendingTags.insert(tag)
                            continue
                        }
                        progress(.init(step: .writeRuleSet, message: "写入 rule-set(\(tag)).srs"))
                        let target = stagingRuleSetDir.appendingPathComponent("\(tag).srs", isDirectory: false)
                        try data.write(to: target, options: [.atomic])
                        downloadedTags.insert(tag)
                    } catch {
                        pendingTags.insert(tag)
                    }
                }
                if !pendingTags.isEmpty {
                    progress(.init(step: .downloadRuleSet, message: "部分 rule-set 需要连接后初始化：\(Array(pendingTags).sorted().joined(separator: ", "))"))
                }
            }

            var urlByProvider = await SharedPreferences.installedProviderRuleSetURLByProvider.get()
            urlByProvider[providerID] = ruleSetURLMap
            await SharedPreferences.installedProviderRuleSetURLByProvider.set(urlByProvider)

            let fullConfigData = try patchConfigRuleSetsToLocalPaths(configData: configData, providerID: providerID, downloadedRuleSetTags: downloadedTags)
            let stagingFullURL = stagingDir.appendingPathComponent("config_full.json", isDirectory: false)
            try fullConfigData.write(to: stagingFullURL, options: [.atomic])

            let activeConfigData: Data
            if pendingTags.isEmpty {
                activeConfigData = fullConfigData
            } else {
                let (bootstrapData, _) = try makeBootstrapConfigData(fullConfigData: fullConfigData, removingRemoteRuleSets: true)
                let stagingBootstrapURL = stagingDir.appendingPathComponent("config_bootstrap.json", isDirectory: false)
                try bootstrapData.write(to: stagingBootstrapURL, options: [.atomic])
                activeConfigData = bootstrapData
            }

            progress(.init(step: .writeConfig, message: "写入 config.json"))
            let stagingConfigURL = stagingDir.appendingPathComponent("config.json", isDirectory: false)
            try activeConfigData.write(to: stagingConfigURL, options: [.atomic])

            let providerConfigURL = FilePath.providerConfigFile(providerID: providerID)
            let backupDir = backupRoot.appendingPathComponent("\(providerID)-\(UUID().uuidString)", isDirectory: true)
            if fm.fileExists(atPath: providerDir.path) {
                try fm.moveItem(at: providerDir, to: backupDir)
            }
            try fm.moveItem(at: stagingDir, to: providerDir)
            if fm.fileExists(atPath: backupDir.path) {
                try? fm.removeItem(at: backupDir)
            }

            progress(.init(step: .registerProfile, message: "注册到 Profiles"))
            let existingProfileID = await providerProfileID(providerID: providerID)
            let installedProfileID: Int64
            if let existingProfileID, let existing = try await ProfileManager.get(existingProfileID) {
                existing.name = provider.name
                existing.path = providerConfigURL.path
                try await ProfileManager.update(existing)
                installedProfileID = existingProfileID
            } else {
                let profile = Profile(
                    name: provider.name,
                    type: .local,
                    path: providerConfigURL.path
                )
                try await ProfileManager.create(profile)
                installedProfileID = profile.mustID
            }

            if !packageHash.isEmpty {
                var providerHashMap = await SharedPreferences.installedProviderPackageHash.get()
                providerHashMap[providerID] = packageHash
                await SharedPreferences.installedProviderPackageHash.set(providerHashMap)
            }
            var profileToProvider = await SharedPreferences.installedProviderIDByProfile.get()
            profileToProvider[String(installedProfileID)] = providerID
            await SharedPreferences.installedProviderIDByProfile.set(profileToProvider)

            var pendingByProvider = await SharedPreferences.installedProviderPendingRuleSetTags.get()
            if pendingTags.isEmpty {
                pendingByProvider.removeValue(forKey: providerID)
            } else {
                pendingByProvider[providerID] = Array(pendingTags).sorted()
            }
            await SharedPreferences.installedProviderPendingRuleSetTags.set(pendingByProvider)

            if selectAfterInstall {
                await SharedPreferences.selectedProfileID.set(installedProfileID)
            }

            progress(.init(step: .finalize, message: "完成"))
            await MainActor.run {
                NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                NotificationCenter.default.post(
                    name: .providerConfigDidUpdate,
                    object: nil,
                    userInfo: ["provider_id": providerID, "profile_id": installedProfileID]
                )
            }
        } catch {
            try? fm.removeItem(at: stagingDir)
            throw error
        }
    }

    private func extractRemoteRuleSetURLMap(configData: Data) -> [String: String] {
        guard let obj = (try? JSONSerialization.jsonObject(with: configData, options: [.fragmentsAllowed])) as? [String: Any] else {
            return [:]
        }
        guard let route = obj["route"] as? [String: Any] else { return [:] }
        guard let ruleSets = route["rule_set"] as? [Any] else { return [:] }
        var result: [String: String] = [:]
        for any in ruleSets {
            guard let rs = any as? [String: Any] else { continue }
            guard (rs["type"] as? String) == "remote" else { continue }
            guard let tag = rs["tag"] as? String, !tag.isEmpty else { continue }
            guard let url = rs["url"] as? String, !url.isEmpty else { continue }
            result[tag] = url
        }
        return result
    }

    public func installProviderFromImportedConfig(
        providerID rawProviderID: String?,
        providerName rawProviderName: String?,
        packageHash rawPackageHash: String?,
        configData: Data,
        routingRulesData: Data?,
        ruleSetURLMap overrideRuleSetURLMap: [String: String]?,
        selectAfterInstall: Bool,
        progress: @Sendable (InstallProgress) -> Void
    ) async throws {
        let fm = FileManager.default
        let providerID = (rawProviderID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let providerName = (rawProviderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let packageHash = (rawPackageHash ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProviderID = providerID.isEmpty ? "imported-\(UUID().uuidString.lowercased())" : providerID
        let resolvedProviderName = providerName.isEmpty ? "导入供应商" : providerName

        let providerDir = FilePath.providerDirectory(providerID: resolvedProviderID)
        let providersRoot = providerDir.deletingLastPathComponent()
        let stagingRoot = providersRoot.appendingPathComponent(".staging", isDirectory: true)
        let backupRoot = providersRoot.appendingPathComponent(".backup", isDirectory: true)
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true, attributes: nil)

        let stagingDir = stagingRoot.appendingPathComponent("\(resolvedProviderID)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: nil)

        do {
            progress(.init(step: .validateConfig, message: "解析配置文件"))
            _ = try JSONSerialization.jsonObject(with: configData, options: [.fragmentsAllowed])
            try validateTunStackCompatibilityForInstall(configData)

            if let routingRulesData, !routingRulesData.isEmpty {
                progress(.init(step: .writeRoutingRules, message: "写入 routing_rules.json"))
                let stagingRulesURL = stagingDir.appendingPathComponent("routing_rules.json", isDirectory: false)
                try routingRulesData.write(to: stagingRulesURL, options: [.atomic])
            } else {
                progress(.init(step: .writeRoutingRules, message: "跳过：未提供 routing_rules.json"))
            }

            let extracted = extractRemoteRuleSetURLMap(configData: configData)
            let ruleSetURLMap = (overrideRuleSetURLMap?.isEmpty == false) ? (overrideRuleSetURLMap ?? [:]) : extracted

            var downloadedTags: Set<String> = []
            var pendingTags: Set<String> = []
            if ruleSetURLMap.isEmpty {
                progress(.init(step: .downloadRuleSet, message: "跳过：配置未包含 rule-set"))
            } else {
                let stagingRuleSetDir = stagingDir.appendingPathComponent("rule-set", isDirectory: true)
                try fm.createDirectory(at: stagingRuleSetDir, withIntermediateDirectories: true, attributes: nil)
                for (tag, urlString) in ruleSetURLMap {
                    guard let u = URL(string: urlString) else { continue }
                    progress(.init(step: .downloadRuleSet, message: "下载 rule-set(\(tag))：\(u.absoluteString)"))
                    do {
                        let data = try await fetchData(u, timeout: 20)
                        if data.isEmpty {
                            pendingTags.insert(tag)
                            continue
                        }
                        progress(.init(step: .writeRuleSet, message: "写入 rule-set(\(tag)).srs"))
                        let target = stagingRuleSetDir.appendingPathComponent("\(tag).srs", isDirectory: false)
                        try data.write(to: target, options: [.atomic])
                        downloadedTags.insert(tag)
                    } catch {
                        pendingTags.insert(tag)
                    }
                }
                if !pendingTags.isEmpty {
                    progress(.init(step: .downloadRuleSet, message: "部分 rule-set 需要连接后初始化：\(Array(pendingTags).sorted().joined(separator: ", "))"))
                }
            }

            var urlByProvider = await SharedPreferences.installedProviderRuleSetURLByProvider.get()
            urlByProvider[resolvedProviderID] = ruleSetURLMap
            await SharedPreferences.installedProviderRuleSetURLByProvider.set(urlByProvider)

            let fullConfigData = try patchConfigRuleSetsToLocalPaths(configData: configData, providerID: resolvedProviderID, downloadedRuleSetTags: downloadedTags)
            let stagingFullURL = stagingDir.appendingPathComponent("config_full.json", isDirectory: false)
            try fullConfigData.write(to: stagingFullURL, options: [.atomic])

            let activeConfigData: Data
            if pendingTags.isEmpty {
                activeConfigData = fullConfigData
            } else {
                let (bootstrapData, _) = try makeBootstrapConfigData(fullConfigData: fullConfigData, removingRemoteRuleSets: true)
                let stagingBootstrapURL = stagingDir.appendingPathComponent("config_bootstrap.json", isDirectory: false)
                try bootstrapData.write(to: stagingBootstrapURL, options: [.atomic])
                activeConfigData = bootstrapData
            }

            progress(.init(step: .writeConfig, message: "写入 config.json"))
            let stagingConfigURL = stagingDir.appendingPathComponent("config.json", isDirectory: false)
            try activeConfigData.write(to: stagingConfigURL, options: [.atomic])

            let providerConfigURL = FilePath.providerConfigFile(providerID: resolvedProviderID)
            let backupDir = backupRoot.appendingPathComponent("\(resolvedProviderID)-\(UUID().uuidString)", isDirectory: true)
            if fm.fileExists(atPath: providerDir.path) {
                try fm.moveItem(at: providerDir, to: backupDir)
            }
            try fm.moveItem(at: stagingDir, to: providerDir)
            if fm.fileExists(atPath: backupDir.path) {
                try? fm.removeItem(at: backupDir)
            }

            progress(.init(step: .registerProfile, message: "注册到 Profiles"))
            let existingProfileID = await providerProfileID(providerID: resolvedProviderID)
            let installedProfileID: Int64
            if let existingProfileID, let existing = try await ProfileManager.get(existingProfileID) {
                existing.name = resolvedProviderName
                existing.path = providerConfigURL.path
                try await ProfileManager.update(existing)
                installedProfileID = existingProfileID
            } else {
                let profile = Profile(
                    name: resolvedProviderName,
                    type: .local,
                    path: providerConfigURL.path
                )
                try await ProfileManager.create(profile)
                installedProfileID = profile.mustID
            }

            var profileToProvider = await SharedPreferences.installedProviderIDByProfile.get()
            profileToProvider[String(installedProfileID)] = resolvedProviderID
            await SharedPreferences.installedProviderIDByProfile.set(profileToProvider)

            if !packageHash.isEmpty {
                var providerHashMap = await SharedPreferences.installedProviderPackageHash.get()
                providerHashMap[resolvedProviderID] = packageHash
                await SharedPreferences.installedProviderPackageHash.set(providerHashMap)
            }

            var pendingByProvider = await SharedPreferences.installedProviderPendingRuleSetTags.get()
            if pendingTags.isEmpty {
                pendingByProvider.removeValue(forKey: resolvedProviderID)
            } else {
                pendingByProvider[resolvedProviderID] = Array(pendingTags).sorted()
            }
            await SharedPreferences.installedProviderPendingRuleSetTags.set(pendingByProvider)

            if selectAfterInstall {
                await SharedPreferences.selectedProfileID.set(installedProfileID)
            }

            progress(.init(step: .finalize, message: "完成"))
            await MainActor.run {
                NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                NotificationCenter.default.post(
                    name: .providerConfigDidUpdate,
                    object: nil,
                    userInfo: ["provider_id": resolvedProviderID, "profile_id": installedProfileID]
                )
            }
        } catch {
            try? fm.removeItem(at: stagingDir)
            throw error
        }
    }

    public func pendingRuleSetTags(providerID: String) async -> [String] {
        let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
        return pending[providerID] ?? []
    }

    public func initializePendingRuleSetsForSelectedProfile(progress: @Sendable (String) -> Void = { _ in }) async -> Bool {
        let selectedProfileID = await SharedPreferences.selectedProfileID.get()
        if selectedProfileID < 0 { return false }
        let profileToProvider = await SharedPreferences.installedProviderIDByProfile.get()
        guard let providerID = profileToProvider[String(selectedProfileID)], !providerID.isEmpty else { return false }

        var pendingByProvider = await SharedPreferences.installedProviderPendingRuleSetTags.get()
        var pending = pendingByProvider[providerID] ?? []
        if pending.isEmpty { return false }

        let urlByProvider = await SharedPreferences.installedProviderRuleSetURLByProvider.get()
        let urlMap = urlByProvider[providerID] ?? [:]
        if urlMap.isEmpty { return false }

        let fm = FileManager.default
        let providerDir = FilePath.providerDirectory(providerID: providerID)
        let ruleSetDir = FilePath.providerRuleSetDirectory(providerID: providerID)
        try? fm.createDirectory(at: ruleSetDir, withIntermediateDirectories: true, attributes: nil)

        var succeeded: Set<String> = []
        for tag in pending {
            guard let urlString = urlMap[tag], let u = URL(string: urlString) else { continue }
            progress("初始化下载 rule-set(\(tag))：\(u.absoluteString)")
            do {
                let data = try await fetchData(u, timeout: 12)
                if data.isEmpty { continue }
                let target = ruleSetDir.appendingPathComponent("\(tag).srs", isDirectory: false)
                try data.write(to: target, options: [.atomic])
                succeeded.insert(tag)
            } catch {
                continue
            }
        }

        if succeeded.isEmpty { return false }

        let fullConfigURL = providerDir.appendingPathComponent("config_full.json", isDirectory: false)
        guard let fullConfigData = try? Data(contentsOf: fullConfigURL), !fullConfigData.isEmpty else { return false }

        let patchedFull = (try? patchConfigRuleSetsToLocalPaths(configData: fullConfigData, providerID: providerID, downloadedRuleSetTags: succeeded)) ?? fullConfigData
        try? patchedFull.write(to: fullConfigURL, options: [.atomic])

        pending.removeAll(where: { succeeded.contains($0) })
        if pending.isEmpty {
            let activeURL = FilePath.providerConfigFile(providerID: providerID)
            try? patchedFull.write(to: activeURL, options: [.atomic])
            pendingByProvider.removeValue(forKey: providerID)
        } else {
            let (bootstrapData, _) = (try? makeBootstrapConfigData(fullConfigData: patchedFull, removingRemoteRuleSets: true)) ?? (patchedFull, [])
            let activeURL = FilePath.providerConfigFile(providerID: providerID)
            try? bootstrapData.write(to: activeURL, options: [.atomic])
            pendingByProvider[providerID] = pending
        }
        await SharedPreferences.installedProviderPendingRuleSetTags.set(pendingByProvider)

        return true
    }
}
