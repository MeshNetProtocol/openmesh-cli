import SwiftUI
import NetworkExtension

struct MainTabView: View {
    var body: some View {
        TabView {
            // Use the new HomeTabView component that contains all VPN functionality
            HomeTabView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
            
            
            MeTabView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("我的")
                }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
