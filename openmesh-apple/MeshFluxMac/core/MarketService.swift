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
    
    public func fetchProviders() async throws -> [TrafficProvider] {
        guard let url = URL(string: "\(baseUrl)/providers") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
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
    
    private func fetchProviderDetail(providerID: String, fallbackDetailURL: String? = nil) async throws -> ProviderDetailResponse {
        let urlString = fallbackDetailURL ?? "\(baseUrl)/providers/\(providerID)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ProviderDetailResponse.self, from: data)
        guard response.ok else {
            throw NSError(domain: "MarketService", code: 3, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"])
        }
        return response
    }

    public func downloadAndInstallProfile(provider: TrafficProvider) async throws {
        let detail = try await fetchProviderDetail(providerID: provider.id, fallbackDetailURL: provider.detail_url)
        let packageHash = detail.package?.package_hash ?? provider.package_hash ?? ""
        let packageFiles = detail.package?.files ?? []
        let configURLString = packageFiles.first(where: { $0.type == "config" })?.url ?? provider.config_url
        guard let configEndpointURL = URL(string: configURLString) else { throw URLError(.badURL) }

        let (configData, _) = try await URLSession.shared.data(from: configEndpointURL)
        guard let configString = String(data: configData, encoding: .utf8), !configString.isEmpty else {
            throw NSError(domain: "MarketService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty config content"])
        }

        if let rulesURLString = packageFiles.first(where: { $0.type == "force_proxy" })?.url,
           let rulesURL = URL(string: rulesURLString) {
            let (rulesData, _) = try await URLSession.shared.data(from: rulesURL)
            let providerDir = FilePath.providerDirectory(providerID: provider.id)
            try FileManager.default.createDirectory(at: providerDir, withIntermediateDirectories: true, attributes: nil)
            let rulesFileURL = FilePath.providerRoutingRulesFile(providerID: provider.id)
            try rulesData.write(to: rulesFileURL, options: [.atomic])
        }
        
        // 1. Get next ID for filename
        let nextId = try await ProfileManager.nextID()
        
        // 2. Prepare file path
        // Note: Profile.path is relative to AppGroup/configs/ usually, but DefaultProfileHelper uses absolute path in `Profile(...)` init?
        // Let's check DefaultProfileHelper again.
        // It says: path: configURL.path (absolute path)
        // But Profile+RW.swift says: try String(contentsOfFile: path, ...)
        // If path is absolute, it works.
        // However, Profile+RW.swift also has logic for iCloud which uses relative path?
        // Let's stick to what DefaultProfileHelper does: absolute path.
        
        let configsDir = FilePath.configsDirectory
        try FileManager.default.createDirectory(at: configsDir, withIntermediateDirectories: true, attributes: nil)
        
        let filename = "config_\(nextId).json"
        let configURL = configsDir.appendingPathComponent(filename)
        
        // 3. Write file
        try configString.write(to: configURL, atomically: true, encoding: .utf8)
        
        // 4. Create Profile
        // We use provider name. If it exists, maybe append (1)?
        // For now, let's just use the name.
        let profile = Profile(
            name: provider.name,
            type: .local,
            path: configURL.path
        )
        
        try await ProfileManager.create(profile)

        if !packageHash.isEmpty {
            var providerHashMap = await SharedPreferences.installedProviderPackageHash.get()
            providerHashMap[provider.id] = packageHash
            await SharedPreferences.installedProviderPackageHash.set(providerHashMap)
        }
        var profileToProvider = await SharedPreferences.installedProviderIDByProfile.get()
        profileToProvider[String(profile.mustID)] = provider.id
        await SharedPreferences.installedProviderIDByProfile.set(profileToProvider)
        
        // 5. Select and Notify
        await SharedPreferences.selectedProfileID.set(profile.mustID)
        await MainActor.run {
            NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
        }
    }
}
