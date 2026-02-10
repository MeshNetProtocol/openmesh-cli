import Foundation
import VPNLibrary

struct TrafficProvider: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let config_url: String
    let tags: [String]
    let author: String
    let updated_at: String
    let provider_hash: String?
    let package_hash: String?
    let price_per_gb_usd: Double?
    let detail_url: String?
}

private struct MarketResponse: Codable {
    let ok: Bool
    let data: [TrafficProvider]?
    let error: String?
}

private struct MarketManifestResponse: Codable {
    let ok: Bool
    let market_version: Int?
    let updated_at: String?
    let providers: [TrafficProvider]?
    let error: String?
}

final class MarketService {
    static let shared = MarketService()

    private let baseURLs = [
        "https://openmesh-api.ribencong.workers.dev/api/v1",
    ]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private var marketManifestCacheFileURL: URL {
        FilePath.meshFluxSharedDataDirectory
            .appendingPathComponent("market_manifest.json", isDirectory: false)
    }

    private var marketRecommendedCacheFileURL: URL {
        FilePath.meshFluxSharedDataDirectory
            .appendingPathComponent("market_recommended.json", isDirectory: false)
    }

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

    func fetchProviders() async throws -> [TrafficProvider] {
        try await firstSuccessful { base in
            guard let url = URL(string: "\(base)/providers") else {
                throw URLError(.badURL)
            }
            let data = try await fetchData(url, timeout: 30)
            let response = try JSONDecoder().decode(MarketResponse.self, from: data)
            if let providers = response.data {
                return providers
            }
            throw NSError(
                domain: "MarketService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"]
            )
        }
    }

    func fetchMarketProvidersCached() async throws -> [TrafficProvider] {
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

    func fetchMarketRecommendedCached() async throws -> [TrafficProvider] {
        do {
            return try await firstSuccessful { base in
                guard let url = URL(string: "\(base)/market/recommended") else {
                    throw URLError(.badURL)
                }
                let data = try await fetchData(url, timeout: 20)
                let response = try JSONDecoder().decode(MarketResponse.self, from: data)
                guard response.ok, let providers = response.data else {
                    throw NSError(
                        domain: "MarketService",
                        code: 11,
                        userInfo: [NSLocalizedDescriptionKey: response.error ?? "Unknown error"]
                    )
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
}
