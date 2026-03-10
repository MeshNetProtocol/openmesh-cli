import SwiftUI
import NetworkExtension

struct MainTabView: View {
    private enum ActiveModal: Identifiable {
        case bootstrap
        case importConfig
        case installConfig(ImportInstallContext)

        var id: String {
            switch self {
            case .bootstrap:
                return "bootstrap"
            case .importConfig:
                return "importConfig"
            case .installConfig(let context):
                return "install-\(context.id.uuidString)"
            }
        }
    }

    @State private var selectedTab: Int = 0
    @State private var activeModal: ActiveModal?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                HomeTabView(
                    onOpenBootstrap: {
                        activeModal = .bootstrap
                    },
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
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .bootstrap:
                BootstrapFetchWizardIOS(
                    onImportConfig: {
                        transitionModal(to: .importConfig)
                    },
                    onInstallConfig: { context in
                        transitionModal(to: .installConfig(context))
                    }
                )
            case .importConfig:
                NavigationView {
                    OfflineImportViewIOS()
                }
            case .installConfig(let context):
                ImportedInstallWizardView(
                    provider: context.pseudoProvider,
                    context: context,
                    onCompleted: {
                        NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                        activeModal = nil
                    }
                )
            }
        }
    }

    private func transitionModal(to next: ActiveModal) {
        activeModal = nil
        DispatchQueue.main.async {
            activeModal = next
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
