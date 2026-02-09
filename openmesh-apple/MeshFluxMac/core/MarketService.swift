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

struct ProviderDetailResponse: Codable {
    let ok: Bool
    let provider: TrafficProvider?
    let package: ProviderPackage?
    let error: String?
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
    
    // For local testing, point to local worker
    // In production this should be https://market.openmesh.network/api/v1
    // private let baseUrl = "https://openmesh-api.ribencong.workers.dev/api/v1"
    private let baseUrl = "http://localhost:8787/api/v1"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private func fetchData(_ url: URL, timeout: TimeInterval = 15) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let (data, _) = try await session.data(for: req)
        return data
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
        case noteRuleSetDownload
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
        guard let url = URL(string: "\(baseUrl)/providers") else {
            throw URLError(.badURL)
        }
        
        let data = try await fetchData(url)
        
        if let str = String(data: data, encoding: .utf8) {
             print("MarketService fetchProviders response: \(str)")
        }
        
        let response = try JSONDecoder().decode(MarketResponse.self, from: data)
        
        if let providers = response.data {
            return providers
        } else {
            throw NSError(domain: "MarketService", code: 1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
        }
    }
    
    func fetchProviderDetail(providerID: String, fallbackDetailURL: String? = nil) async throws -> ProviderDetailResponse {
        let urlString = fallbackDetailURL ?? "\(baseUrl)/providers/\(providerID)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let data = try await fetchData(url)
        let response = try JSONDecoder().decode(ProviderDetailResponse.self, from: data)
        guard response.ok else {
            throw NSError(domain: "MarketService", code: 3, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
        }
        return response
    }

    private func extractRemoteRuleSetURLs(configData: Data) -> [String] {
        guard let obj = (try? JSONSerialization.jsonObject(with: configData, options: [.fragmentsAllowed])) as? [String: Any] else {
            return []
        }
        guard let route = obj["route"] as? [String: Any] else { return [] }
        guard let ruleSets = route["rule_set"] as? [Any] else { return [] }
        var urls: [String] = []
        for any in ruleSets {
            guard let rs = any as? [String: Any] else { continue }
            guard (rs["type"] as? String) == "remote" else { continue }
            guard let url = rs["url"] as? String, !url.isEmpty else { continue }
            urls.append(url)
        }
        return urls
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
        progress(.init(step: .fetchDetail, message: "读取供应商详情"))
        let detail = try await fetchProviderDetail(providerID: provider.id, fallbackDetailURL: provider.detail_url)

        let packageHash = detail.package?.package_hash ?? provider.package_hash ?? ""
        let packageFiles = detail.package?.files ?? []
        let providerID = provider.id

        let providerDir = FilePath.providerDirectory(providerID: providerID)
        try FileManager.default.createDirectory(at: providerDir, withIntermediateDirectories: true, attributes: nil)

        let configURLString = packageFiles.first(where: { $0.type == "config" })?.url ?? provider.config_url
        guard let configEndpointURL = URL(string: configURLString) else { throw URLError(.badURL) }

        progress(.init(step: .downloadConfig, message: "下载配置文件：\(configEndpointURL.absoluteString)"))
        let downloadedConfigData = try await fetchData(configEndpointURL, timeout: 20)
        guard !downloadedConfigData.isEmpty else {
            throw NSError(domain: "MarketService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty config content"])
        }

        progress(.init(step: .validateConfig, message: "解析配置文件"))
        let configData = downloadedConfigData
        _ = try JSONSerialization.jsonObject(with: configData, options: [.fragmentsAllowed])
        try validateTunStackCompatibilityForInstall(configData)

        progress(.init(step: .writeConfig, message: "写入 config.json"))
        let providerConfigURL = FilePath.providerConfigFile(providerID: providerID)
        try configData.write(to: providerConfigURL, options: [.atomic])

        let rulesURLString = packageFiles.first(where: { $0.type == "force_proxy" })?.url
        if let rulesURLString, let rulesURL = URL(string: rulesURLString) {
            progress(.init(step: .downloadRoutingRules, message: "下载 routing_rules.json：\(rulesURL.absoluteString)"))
            let rulesData = try await fetchData(rulesURL, timeout: 20)
            progress(.init(step: .writeRoutingRules, message: "写入 routing_rules.json"))
            let rulesFileURL = FilePath.providerRoutingRulesFile(providerID: providerID)
            try rulesData.write(to: rulesFileURL, options: [.atomic])
        } else {
            progress(.init(step: .downloadRoutingRules, message: "跳过：该供应商未提供 routing_rules.json"))
        }

        let ruleSetURLs = extractRemoteRuleSetURLs(configData: configData)
        if ruleSetURLs.isEmpty {
            progress(.init(step: .noteRuleSetDownload, message: "该配置未声明远程 rule-set"))
        } else {
            progress(.init(step: .noteRuleSetDownload, message: "连接时由 sing-box 下载 rule-set：\(ruleSetURLs.joined(separator: ", "))"))
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

        if selectAfterInstall {
            await SharedPreferences.selectedProfileID.set(installedProfileID)
        }

        progress(.init(step: .finalize, message: "完成"))
        await MainActor.run {
            NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
        }
    }
}
