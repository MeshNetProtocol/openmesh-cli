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
        root = (WalletStore.hasWallet() && PINStore.hasPIN()) ? .main : .onboarding
    }
    
    func enterMain() { root = .main }
    func enterOnboarding() { root = .onboarding }
}
