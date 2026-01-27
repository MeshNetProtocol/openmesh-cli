import Foundation

enum RoutingMode: String {
    case rule
    case global
}

/// Stores the routing mode used by the VPN extension.
///
/// - `rule`: match `routing_rules.json` => proxy, otherwise direct (current behavior).
/// - `global`: all traffic uses proxy (global mode).
///
let appGroupMain   = "group.com.meshnetprotocol.OpenMesh"
let appGroupMacSys = "group.com.meshnetprotocol.OpenMesh.macsys"
enum RoutingModeStore {
    static var appGroupID: String {
        Bundle.main.bundleIdentifier?.hasSuffix(".macsys") == true
            ? appGroupMacSys
            : appGroupMain
    }
    
    static let relativeDir = "MeshFlux"
    static let filename = "routing_mode.json"

    static func read() -> RoutingMode {
        guard let url = appGroupFileURL() else { return .rule }
        guard let data = try? Data(contentsOf: url) else { return .rule }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return .rule }
        guard let dict = obj as? [String: Any] else { return .rule }
        guard let modeStr = dict["mode"] as? String else { return .rule }
        return RoutingMode(rawValue: modeStr) ?? .rule
    }

    static func write(_ mode: RoutingMode) {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        let dirURL = groupURL.appendingPathComponent(relativeDir, isDirectory: true)
        do {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        let url = dirURL.appendingPathComponent(filename, isDirectory: false)
        let obj: [String: Any] = ["mode": mode.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static func appGroupFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        return groupURL.appendingPathComponent(relativeDir, isDirectory: true).appendingPathComponent(filename, isDirectory: false)
    }
}

