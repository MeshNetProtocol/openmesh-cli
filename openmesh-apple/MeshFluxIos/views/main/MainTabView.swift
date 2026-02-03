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
