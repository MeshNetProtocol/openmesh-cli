import SwiftUI
import Foundation
import VPNLibrary
import OpenMeshGo

@main
struct OpenMeshApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var networkManager = NetworkManager()

    init() {
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
    }

    /// Align with MeshFluxMac / sing-box: main app must call OMLibboxSetup with the same App Group paths
    /// so StatusCommandClient / GroupCommandClient / ConnectionCommandClient can connect to extension's command.sock.
    private static func configureLibbox() {
        let options = OMLibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.path
        options.workingPath = FilePath.workingDirectory.path
        options.tempPath = FilePath.cacheDirectory.path
        var err: NSError?
        OMLibboxSetup(options, &err)
        if let err { NSLog("MeshFlux iOS OMLibboxSetup failed: %@", err.localizedDescription) }
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
                    Self.configureLibbox()
                    GoEngine.bootstrapOnFirstLaunchAfterInstall()
                    router.refresh()
                    Task { await DefaultProfileHelper.ensureDefaultProfileIfNeeded() }
                }
        }
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
