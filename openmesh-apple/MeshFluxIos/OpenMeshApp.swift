import SwiftUI
import Foundation
import VPNLibrary

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
