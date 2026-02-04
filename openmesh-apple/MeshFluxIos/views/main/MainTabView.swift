import SwiftUI
import NetworkExtension

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationView {
                HomeTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }

            NavigationView {
                MeTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "chart.bar.fill")
                Text("流量市场")
            }

            NavigationView {
                SettingsTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "gearshape")
                Text("设置")
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
