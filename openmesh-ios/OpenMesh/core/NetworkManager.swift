import Foundation
import SwiftUI
import Combine

// 定义支持的网络
struct Network: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let displayName: String
}

class NetworkManager: ObservableObject {
    @Published var currentNetwork: Network
    
    static let supportedNetworks = [
        Network(name: "base-mainnet", displayName: "Base 主网"),
        Network(name: "base-testnet", displayName: "Base 测试网")
    ]
    
    init() {
        // 从UserDefaults中获取上次选择的网络，如果没有则默认选择第一个
        let lastSelectedNetwork = UserDefaults.standard.string(forKey: "last_selected_network") ?? "base-mainnet"
        let defaultNetwork = Self.supportedNetworks.first { $0.name == lastSelectedNetwork } ?? Self.supportedNetworks[0]
        self.currentNetwork = defaultNetwork
    }
    
    func selectNetwork(_ network: Network) {
        self.currentNetwork = network
        UserDefaults.standard.set(network.name, forKey: "last_selected_network")
    }
    
    func getNetworkByName(_ name: String) -> Network? {
        return Self.supportedNetworks.first { $0.name == name }
    }
}