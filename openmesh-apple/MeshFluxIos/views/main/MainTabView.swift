import SwiftUI
import NetworkExtension

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                HomeTabView(
                    onOpenMarket: {
                        selectedTab = 2
                    },
                    onOpenImport: {
                        selectedTab = 2
                        NotificationCenter.default.post(name: .openOfflineImportFromHome, object: nil)
                    }
                )
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "house")
                Text("Dashboard")
            }
            .tag(0)

            NavigationView {
                MeTabView(isActiveTab: selectedTab == 1)
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

extension Notification.Name {
    static let openOfflineImportFromHome = Notification.Name("openOfflineImportFromHome")
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
