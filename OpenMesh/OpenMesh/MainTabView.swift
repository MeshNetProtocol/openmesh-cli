import SwiftUI

struct MainTabView: View {
        var body: some View {
                TabView {
                        NavigationView {
                                HomeTabView()
                        }
                        .navigationViewStyle(.stack)
                        .tabItem {
                                Label("Home", systemImage: "house.fill")
                        }
                        
                        NavigationView {
                                MeTabView()
                        }
                        .navigationViewStyle(.stack)
                        .tabItem {
                                Label("流量市场", systemImage: "person.crop.circle")
                        }
                        
                        NavigationView {
                                MeTabView()
                        }
                        .navigationViewStyle(.stack)
                        .tabItem {
                                Label("我的", systemImage: "person.crop.circle")
                        }
                }
        }
}

private struct HomeTabView: View {
        var body: some View {
                VStack(spacing: 12) {
                        Text("Home")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Text("TODO: 这里放钱包首页内容")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("Home")
        }
}

private struct MeTabView: View {
        @EnvironmentObject private var router: AppRouter
        private let hud = AppHUD.shared
        
        var body: some View {
                VStack(spacing: 12) {
                        Text("我的")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                        
                        Text("TODO: 这里放账户/设置")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        
                        Button("（调试）清空钱包与 PIN，回到新手流程") {
                                hud.showAlert(
                                        title: "确认清空？",
                                        message: "将删除本机保存的钱包数据与 PIN。你需要助记词才能恢复。",
                                        primaryTitle: "清空并重建",
                                        secondaryTitle: "取消",
                                        tapToDismiss: true,
                                        primaryAction: {
                                                do {
                                                        try WalletStore.clear()
                                                        try PINStore.clear()
                                                        hud.showToast("已清空")
                                                        router.enterOnboarding()
                                                } catch {
                                                        hud.showAlert(
                                                                title: "清空失败",
                                                                message: error.localizedDescription,
                                                                tapToDismiss: true
                                                        )
                                                }
                                        }
                                )
                        }
                        .buttonStyle(.bordered)
                        
                        .padding(.top, 10)
                }
                .padding()
                .navigationTitle("我的")
        }
}
