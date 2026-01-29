//
//  Database.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Database/Databse.swift.
//  Uses SQLite3 (system) instead of GRDB for no extra SPM dependency.
//

import Foundation
import SQLite3

enum Database {
    static let shared = DatabaseConnection()

    /// Synchronous write; run from async via Task {} if needed.
    static func write(_ block: (DatabaseConnection) throws -> Void) throws {
        try block(shared)
    }

    /// Synchronous read; run from async via Task {} if needed.
    static func read<T>(_ block: (DatabaseConnection) throws -> T) throws -> T {
        try block(shared)
    }
}

final class DatabaseConnection {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.meshnetprotocol.OpenMesh.vpnlibrary.db", qos: .userInitiated)

    init() {
        queue.sync { [self] in
            openAndMigrate()
        }
    }

    private func openAndMigrate() {
        do {
            try FileManager.default.createDirectory(at: FilePath.sharedDirectory, withIntermediateDirectories: true)
            let path = FilePath.sharedDirectory.appendingPathComponent("settings.db").path
            if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                throw NSError(domain: "VPNLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database: \(path)"])
            }
            try runMigrations()
        } catch {
            fatalError("Database init: \(error.localizedDescription)")
        }
    }

    private func runMigrations() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                "order" INTEGER NOT NULL,
                type INTEGER NOT NULL DEFAULT 0,
                path TEXT NOT NULL,
                remoteURL TEXT,
                autoUpdate INTEGER NOT NULL DEFAULT 0,
                autoUpdateInterval INTEGER NOT NULL DEFAULT 0,
                lastUpdated REAL
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS preferences (
                name TEXT PRIMARY KEY ON CONFLICT REPLACE NOT NULL,
                data BLOB
            );
            """)
        // Add autoUpdateInterval if missing (legacy DB created before this column)
        if try !hasColumn("profiles", "autoUpdateInterval") {
            try exec("ALTER TABLE profiles ADD COLUMN autoUpdateInterval INTEGER NOT NULL DEFAULT 0;")
        }
    }

    private func exec(_ sql: String) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "VPNLibrary", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "VPNLibrary", code: 3, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    private func hasColumn(_ table: String, _ column: String) throws -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            if name == column { return true }
        }
        return false
    }

    func execute(_ sql: String, _ bind: (() -> Void)? = nil) throws {
        try queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "VPNLibrary", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
            }
            bind?()
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(domain: "VPNLibrary", code: 5, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
            }
        }
    }

    func insertProfile(_ p: Profile) throws {
        try queue.sync {
            let sql = """
            INSERT INTO profiles (name, "order", type, path, remoteURL, autoUpdate, autoUpdateInterval, lastUpdated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            sqlite3_bind_text(stmt, 1, (p.name as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(p.order))
            sqlite3_bind_int(stmt, 3, Int32(p.type.rawValue))
            sqlite3_bind_text(stmt, 4, (p.path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, ((p.remoteURL ?? "") as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 6, p.autoUpdate ? 1 : 0)
            sqlite3_bind_int(stmt, 7, p.autoUpdateInterval)
            if let d = p.lastUpdated { sqlite3_bind_double(stmt, 8, d.timeIntervalSince1970) } else { sqlite3_bind_null(stmt, 8) }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
            p.id = sqlite3_last_insert_rowid(db)
        }
    }

    func getProfile(id: Int64) throws -> Profile? {
        try queue.sync {
            let sql = "SELECT id, name, \"order\", type, path, remoteURL, autoUpdate, autoUpdateInterval, lastUpdated FROM profiles WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return rowToProfile(stmt)
        }
    }

    func getProfile(byName name: String) throws -> Profile? {
        try queue.sync {
            let sql = "SELECT id, name, \"order\", type, path, remoteURL, autoUpdate, autoUpdateInterval, lastUpdated FROM profiles WHERE name = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return rowToProfile(stmt)
        }
    }

    func updateProfile(_ p: Profile) throws {
        guard let id = p.id else { return }
        try queue.sync {
            let sql = """
            UPDATE profiles SET name = ?, "order" = ?, type = ?, path = ?, remoteURL = ?, autoUpdate = ?, autoUpdateInterval = ?, lastUpdated = ? WHERE id = ?;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            sqlite3_bind_text(stmt, 1, (p.name as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(p.order))
            sqlite3_bind_int(stmt, 3, Int32(p.type.rawValue))
            sqlite3_bind_text(stmt, 4, (p.path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, ((p.remoteURL ?? "") as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 6, p.autoUpdate ? 1 : 0)
            sqlite3_bind_int(stmt, 7, p.autoUpdateInterval)
            if let d = p.lastUpdated { sqlite3_bind_double(stmt, 8, d.timeIntervalSince1970) } else { sqlite3_bind_null(stmt, 8) }
            sqlite3_bind_int64(stmt, 9, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
        }
    }

    func deleteProfile(_ p: Profile) throws {
        guard let id = p.id else { return }
        try queue.sync {
            let sql = "DELETE FROM profiles WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
        }
    }

    func deleteProfile(id: Int64) throws {
        try queue.sync {
            let sql = "DELETE FROM profiles WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
        }
    }

    func listProfiles() throws -> [Profile] {
        try queue.sync {
            let sql = "SELECT id, name, \"order\", type, path, remoteURL, autoUpdate, autoUpdateInterval, lastUpdated FROM profiles ORDER BY \"order\" ASC;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            var list: [Profile] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let p = rowToProfile(stmt) { list.append(p) }
            }
            return list
        }
    }

    func profileCount() throws -> Int {
        try queue.sync {
            let sql = "SELECT COUNT(*) FROM profiles;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    func nextProfileID() throws -> Int64 {
        try queue.sync {
            let sql = "SELECT id FROM profiles ORDER BY id DESC LIMIT 1;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0) + 1
            }
            return 1
        }
    }

    private func rowToProfile(_ stmt: OpaquePointer?) -> Profile? {
        guard let stmt else { return nil }
        let id = sqlite3_column_int64(stmt, 0)
        let name = String(cString: sqlite3_column_text(stmt, 1))
        let order = UInt32(sqlite3_column_int(stmt, 2))
        let typeRaw = sqlite3_column_int(stmt, 3)
        let path = String(cString: sqlite3_column_text(stmt, 4))
        let remoteURL: String? = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let autoUpdate = sqlite3_column_int(stmt, 6) != 0
        let autoUpdateInterval = sqlite3_column_int(stmt, 7)
        var lastUpdated: Date?
        if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
            lastUpdated = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
        }
        let type = ProfileType(rawValue: Int(typeRaw)) ?? .local
        let p = Profile(id: id, name: name, order: order, type: type, path: path, remoteURL: remoteURL, autoUpdate: autoUpdate, autoUpdateInterval: Int32(autoUpdateInterval), lastUpdated: lastUpdated)
        return p
    }

    // MARK: - Preferences

    func getPreference(name: String) throws -> Data? {
        try queue.sync {
            let sql = "SELECT data FROM preferences WHERE name = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let bytes = sqlite3_column_blob(stmt, 0)
            let len = sqlite3_column_bytes(stmt, 0)
            guard let bytes, len > 0 else { return nil }
            return Data(bytes: bytes, count: Int(len))
        }
    }

    func setPreference(name: String, data: Data?) throws {
        try queue.sync {
            if data == nil {
                let sql = "DELETE FROM preferences WHERE name = ?;"
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
                sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            } else {
                let sql = "INSERT OR REPLACE INTO preferences (name, data) VALUES (?, ?);"
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError() }
                sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
                _ = data!.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(data!.count), nil)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
            }
        }
    }

    private func dbError() -> NSError {
        NSError(domain: "VPNLibrary", code: 6, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
}
