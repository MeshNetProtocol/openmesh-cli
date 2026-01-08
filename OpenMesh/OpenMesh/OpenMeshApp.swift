import SwiftUI

@main
struct OpenMeshApp: App {
    @StateObject private var router = AppRouter()
    
    var body: some Scene {
        WindowGroup {
            RootSwitchView()
                .environmentObject(router)
                .overlay {
                    AppHUDOverlay(hud: AppHUD.shared)
                }
                .onAppear {
                    router.refresh()
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
