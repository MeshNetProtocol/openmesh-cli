import SwiftUI
import Foundation

@main
struct OpenMeshApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var networkManager = NetworkManager()

    init() {
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            RootSwitchView()
                .environmentObject(router)
                .environmentObject(networkManager)
                .overlay {
                    AppHUDOverlay(hud: AppHUD.shared)
                }
                .onAppear {
                    GoEngine.bootstrapOnFirstLaunchAfterInstall()
                    router.refresh()
                }
        }
    }
}

private enum RoutingRulesStore {
    static let appGroupID = "group.com.meshnetprotocol.OpenMesh"
    static let relativeDir = "OpenMesh"
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

private struct RootSwitchView: View {
    @EnvironmentObject private var router: AppRouter
    
    var body: some View {
        switch router.root {
        case .onboarding:
            NewAccountView()
        case .main:
            MainTabView()
        }
    }
}
