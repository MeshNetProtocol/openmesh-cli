import Foundation

/// Manages the `routing_rules.json` file used by the VPN extension.
///
/// - Source of truth: `routing_rules.json` shipped in the app bundle. 
/// - Upgrade behavior: if bundled `version` is greater than the App Group file `version`, overwrite it.
enum RoutingRulesStore {
    static var appGroupID: String {
        #if os(iOS)
            appGroupMain
        #else
        Bundle.main.bundleIdentifier?.hasSuffix(".macsys") == true
            ? appGroupMacSys
            : appGroupMain
        #endif
    }
    static let relativeDir = "MeshFlux"
    static let filename = "routing_rules.json"

    static func syncBundledRulesIntoAppGroupIfNeeded() {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        guard let bundledURL = Bundle.main.url(forResource: "routing_rules", withExtension: "json") else { return }

        let destDir = groupURL.appendingPathComponent(relativeDir, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        let destURL = destDir.appendingPathComponent(filename, isDirectory: false)

        guard let bundledVersion = readVersion(from: bundledURL) else { return }
        let existingVersion = readVersion(from: destURL)

        if existingVersion == nil {
            copy(bundledURL: bundledURL, to: destURL)
            return
        }

        if let existingVersion, bundledVersion > existingVersion {
            copy(bundledURL: bundledURL, to: destURL)
        }
    }

    private static func copy(bundledURL: URL, to destURL: URL) {
        do {
            let data = try Data(contentsOf: bundledURL)
            try data.write(to: destURL, options: [.atomic])
        } catch {
            // Ignore.
        }
    }

    private static func readVersion(from url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        guard let dict = obj as? [String: Any] else { return nil }
        if let v = dict["version"] as? Int { return v }
        if let v = dict["version"] as? NSNumber { return v.intValue }
        if let v = dict["version"] as? String { return Int(v) }
        return nil
    }
}
