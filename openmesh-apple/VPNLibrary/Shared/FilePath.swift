//
//  FilePath.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Shared/FilePath.swift.
//  Uses OpenMesh App Group: group.com.meshnetprotocol.OpenMesh
//

import Foundation

public enum FilePath {
    /// Main app / app-level extension use this package name and group.
    public static let packageName = "com.meshnetprotocol.OpenMesh"
}

public extension FilePath {
    static let groupName = "group.\(packageName)"

    private static let defaultSharedDirectory: URL! = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)

    #if os(iOS)
        static let sharedDirectory = defaultSharedDirectory!
    #elseif os(tvOS)
        static let sharedDirectory = defaultSharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(macOS)
        static var sharedDirectory: URL! = defaultSharedDirectory
    #endif

    #if os(iOS)
        static let cacheDirectory = sharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(tvOS)
        static let cacheDirectory = sharedDirectory
    #elseif os(macOS)
        static var cacheDirectory: URL {
            sharedDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
    #endif

    #if os(macOS)
        static var workingDirectory: URL {
            cacheDirectory.appendingPathComponent("Working", isDirectory: true)
        }
    #else
        static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)
    #endif

    /// Directory for profile config JSON files (config_1.json, etc.).
    static var configsDirectory: URL {
        sharedDirectory.appendingPathComponent("configs", isDirectory: true)
    }

    /// App Group path for main-app heartbeat; extension reads this to detect if main app is still alive.
    /// If extension sees no update for 3 intervals (~30s), it will stop VPN (e.g. after main app was killed).
    static var appHeartbeatFile: URL {
        sharedDirectory.appendingPathComponent("MeshFlux", isDirectory: true).appendingPathComponent("app_heartbeat", isDirectory: false)
    }

    static var iCloudDirectory = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true) ?? URL(string: "stub")!
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
