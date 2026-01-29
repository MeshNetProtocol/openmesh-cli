//
//  ProfileManager.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Database/ProfileManager.swift.
//

import Foundation

public enum ProfileManager {
    public nonisolated static func create(_ profile: Profile) async throws {
        profile.order = try await nextOrder()
        try await Task { try Database.write { db in try db.insertProfile(profile) } }.value
    }

    public nonisolated static func get(_ profileID: Int64) async throws -> Profile? {
        try await Task { try Database.read { db in try db.getProfile(id: profileID) } }.value
    }

    public nonisolated static func get(by profileName: String) async throws -> Profile? {
        try await Task { try Database.read { db in try db.getProfile(byName: profileName) } }.value
    }

    public nonisolated static func delete(_ profile: Profile) async throws {
        try await Task { try Database.write { db in try db.deleteProfile(profile) } }.value
    }

    public nonisolated static func delete(by id: Int64) async throws {
        try await Task { try Database.write { db in try db.deleteProfile(id: id) } }.value
    }

    public nonisolated static func update(_ profile: Profile) async throws {
        try await Task { try Database.write { db in try db.updateProfile(profile) } }.value
    }

    public nonisolated static func list() async throws -> [Profile] {
        try await Task { try Database.read { db in try db.listProfiles() } }.value
    }

    public nonisolated static func listRemote() async throws -> [Profile] {
        let all = try await list()
        return all.filter { $0.type == .remote }
    }

    public nonisolated static func listAutoUpdateEnabled() async throws -> [Profile] {
        let all = try await list()
        return all.filter { $0.autoUpdate }
    }

    public nonisolated static func nextID() async throws -> Int64 {
        try await Task { try Database.read { db in try db.nextProfileID() } }.value
    }

    private nonisolated static func nextOrder() async throws -> UInt32 {
        try await Task { try Database.read { db in try UInt32(db.profileCount()) } }.value
    }

    /// Synchronous API for use from Network Extension (no async context).
    /// Uses runBlocking internally; call only from extension startup/reload.
    public static func getBlocking(_ profileID: Int64) throws -> Profile? {
        try runBlocking { try await get(profileID) }
    }
}
