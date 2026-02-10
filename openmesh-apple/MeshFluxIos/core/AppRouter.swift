import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    enum Root: Equatable {
        case onboarding
        case main
    }
    
    @Published var root: Root = .main
    
    init() {
        refresh()
    }
    
    func refresh() {
        root = .main
    }
    
    func enterMain() { root = .main }
    func enterOnboarding() { root = .onboarding }
}
