import SwiftUI
import NetworkExtension

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                HomeTabView {
                    selectedTab = 2
                }
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "house")
                Text("Dashboard")
            }
            .tag(0)

            NavigationView {
                MeTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "wallet.pass.fill")
                Text("钱包")
            }
            .tag(1)

            NavigationView {
                MarketTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "shippingbox.fill")
                Text("Market")
            }
            .tag(2)

            NavigationView {
                SettingsTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "gearshape")
                Text("设置")
            }
            .tag(3)
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
