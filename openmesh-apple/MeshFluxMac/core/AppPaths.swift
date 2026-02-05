//
//  AppPaths.swift
//  MeshFluxMac
//
//  Centralized sandbox-safe directories (Application Support / Caches).
//

import Foundation

enum AppPaths {
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.meshnetprotocol.OpenMesh.mac"
    }

    static var applicationSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var cachesDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    static var applicationSupportRoot: URL {
        applicationSupportDir.appendingPathComponent(bundleID, isDirectory: true)
    }

    static var cachesRoot: URL {
        cachesDir.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// Ensures the app-owned container subdirectories exist.
    @discardableResult
    static func ensureDirs(fileManager: FileManager = .default) throws -> (appSupport: URL, caches: URL) {
        let appSupport = applicationSupportRoot
        let caches = cachesRoot
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        return (appSupport: appSupport, caches: caches)
    }
}

