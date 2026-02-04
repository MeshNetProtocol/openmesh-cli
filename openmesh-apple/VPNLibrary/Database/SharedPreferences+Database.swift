//
//  SharedPreferences+Database.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Database/ShadredPreferences+Database.swift.
//  Uses JSON encoding instead of BinaryCodable for no extra SPM dependency.
//

import Foundation

extension SharedPreferences {
    public class Preference<T: Codable> {
        private let name: String
        private let defaultValue: T

        init(_ name: String, defaultValue: T) {
            self.name = name
            self.defaultValue = defaultValue
        }

        public nonisolated func get() async -> T {
            do {
                return try await SharedPreferences.read(name) ?? defaultValue
            } catch {
                NSLog("VPNLibrary read preferences error: \(error)")
                // Repair: remove corrupted blob so next read returns nil and uses defaultValue without throwing.
                await SharedPreferences.clearPreference(name)
                return defaultValue
            }
        }

        public func getBlocking() -> T {
            return runBlocking { [self] in
                await get()
            }
        }

        public nonisolated func set(_ newValue: T?) async {
            do {
                try await SharedPreferences.write(name, newValue)
            } catch {
                NSLog("VPNLibrary write preferences error: \(error)")
            }
        }
    }

    private nonisolated static func read<T: Codable>(_ name: String) async throws -> T? {
        let data: Data? = try await Task { try Database.read { db in try db.getPreference(name: name) } }.value
        guard let data, !data.isEmpty else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Removes the preference row so next read returns nil (defaultValue). Use when stored blob is not valid JSON (e.g. old/corrupted format).
    private nonisolated static func clearPreference(_ name: String) async {
        do {
            try await Task { try Database.write { db in try db.setPreference(name: name, data: nil) } }.value
        } catch {
            NSLog("VPNLibrary clear preference error: \(error)")
        }
    }

    private nonisolated static func write(_ name: String, _ value: (some Codable)?) async throws {
        if value == nil {
            try await Task { try Database.write { db in try db.setPreference(name: name, data: nil) } }.value
        } else {
            let data = try JSONEncoder().encode(value)
            try await Task { try Database.write { db in try db.setPreference(name: name, data: data) } }.value
        }
    }
}
