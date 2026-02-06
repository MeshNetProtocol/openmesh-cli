import SwiftUI
import Foundation
import VPNLibrary
import OpenMeshGo

@main
struct OpenMeshApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var router = AppRouter()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var vpnController = VPNController()

    init() {
        RoutingRulesStore.syncBundledRulesIntoAppGroupIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            RootSwitchView()
                .environmentObject(router)
                .environmentObject(networkManager)
                .environmentObject(vpnController)
                .overlay {
                    AppHUDOverlay(hud: AppHUD.shared)
                }
                .onAppear {
                    GoEngine.bootstrapOnFirstLaunchAfterInstall()
                    router.refresh()
                    Task { await DefaultProfileHelper.ensureDefaultProfileIfNeeded() }
                    Task { await vpnController.load() }
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
