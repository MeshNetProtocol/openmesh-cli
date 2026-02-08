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
}

struct MarketResponse: Codable {
    let ok: Bool
    let data: [TrafficProvider]?
    let error: String?
}

public class MarketService {
    public static let shared = MarketService()
    
    // For local testing, point to local worker
    // In production this should be https://market.openmesh.network/api/v1
    private let baseUrl = "https://openmesh-api.ribencong.workers.dev/api/v1"
    
    public func fetchProviders() async throws -> [TrafficProvider] {
        guard let url = URL(string: "\(baseUrl)/providers") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Debug: print response
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
    
    public func downloadAndInstallProfile(provider: TrafficProvider) async throws {
        guard let url = URL(string: provider.config_url) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let jsonString = String(data: data, encoding: .utf8), !jsonString.isEmpty else {
            throw NSError(domain: "MarketService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty config content"])
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
        try jsonString.write(to: configURL, atomically: true, encoding: .utf8)
        
        // 4. Create Profile
        // We use provider name. If it exists, maybe append (1)?
        // For now, let's just use the name.
        let profile = Profile(
            name: provider.name,
            type: .local,
            path: configURL.path
        )
        
        try await ProfileManager.create(profile)
        
        // 5. Select and Notify
        await SharedPreferences.selectedProfileID.set(profile.mustID)
        await MainActor.run {
            NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
        }
    }
}
