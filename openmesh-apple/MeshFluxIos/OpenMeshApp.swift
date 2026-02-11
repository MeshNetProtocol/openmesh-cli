import SwiftUI
import Foundation
import VPNLibrary

@main
struct OpenMeshApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var router = AppRouter()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var vpnController = VPNController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootSwitchView()
                .environmentObject(router)
                .environmentObject(networkManager)
                .environmentObject(vpnController)
                .overlay {
                    AppHUDOverlay(hud: AppHUD.shared)
                }
                .onChange(of: scenePhase) { phase in
                    NSLog("OpenMeshApp scenePhase changed: %@", String(describing: phase))
                    vpnController.setAppActive(phase == .active)
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
