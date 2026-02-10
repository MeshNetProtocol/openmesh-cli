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
                Text("Dashboard")
            }

            NavigationView {
                MeTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "wallet.pass.fill")
                Text("钱包")
            }

            NavigationView {
                MarketTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "shippingbox.fill")
                Text("Market")
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
