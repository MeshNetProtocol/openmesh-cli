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
    @AppStorage("openmesh.onboardingComplete") private var onboardingComplete: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("我的")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            
            Text("TODO: 这里放账户/设置")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            
            // 调试用（可删）：允许你快速回到新手流程
            Button("（调试）重置进入新手流程") {
                onboardingComplete = false
            }
            .buttonStyle(.bordered)
            .padding(.top, 10)
        }
        .padding()
        .navigationTitle("我的")
    }
}
