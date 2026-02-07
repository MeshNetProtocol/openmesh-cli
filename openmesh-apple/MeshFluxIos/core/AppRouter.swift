import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    enum Root: Equatable {
        case onboarding
        case main
    }
    
    @Published var root: Root = .onboarding
    
    init() {
        refresh()
    }
    
    func refresh() {
        Task {
            let hasAccount = await Task.detached(priority: .utility) {
                WalletStore.hasWallet() && PINStore.hasPIN()
            }.value
            self.root = hasAccount ? .main : .onboarding
        }
    }
    
    func enterMain() { root = .main }
    func enterOnboarding() { root = .onboarding }
}
