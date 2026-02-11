import SwiftUI
import UIKit

struct MeTabView: View {
        let isActiveTab: Bool
        @Environment(\.scenePhase) private var scenePhase
        @EnvironmentObject private var router: AppRouter
        @EnvironmentObject private var networkManager: NetworkManager
        private let hud = AppHUD.shared
        
        @AppStorage("meshflux.usdc_balance_display") private var usdcBalanceDisplay: String = "0.00"
        @AppStorage("meshflux.usdc_balance_synced") private var usdcBalanceSynced: Bool = false
        
        @State private var address: String = "—"
        @State private var hasWallet: Bool = false
        @State private var hasPIN: Bool = false
        @State private var isLoadingBalance = false
        @State private var lastAutoRefreshAt: Date?
        @State private var balanceRefreshTask: Task<Void, Never>?
        
        private var hasWalletAndPIN: Bool { hasWallet && hasPIN }
        
        var body: some View {
                ScrollView {
                        Group {
                                if hasWalletAndPIN {
                                        VStack(spacing: 14) {
                                                walletCard
                                                networkSelectorCard
                                                x402Card
                                                securityCard
                                                resetCard
                                        }
                                } else {
                                        VStack(spacing: 14) {
                                                createWalletCard
                                        }
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
                .navigationTitle("钱包")
                .onAppear { 
                    reload()
                    triggerAutoRefreshIfNeeded(force: false)
                }
                .onChange(of: isActiveTab) { active in
                    guard active else { return }
                    reload()
                    triggerAutoRefreshIfNeeded(force: false)
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        balanceRefreshTask?.cancel()
                        balanceRefreshTask = nil
                        return
                    }
                    triggerAutoRefreshIfNeeded(force: false)
                }
                .onDisappear {
                    balanceRefreshTask?.cancel()
                    balanceRefreshTask = nil
                }
        }
        
        // MARK: - Cards
        
        private var walletCard: some View {
                Card(title: "钱包") {
                        VStack(spacing: 10) {
                                InfoRow(title: "钱包地址") {
                                        VStack(alignment: .leading, spacing: 6) {
                                                Text(formattedAddress)
                                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                        .foregroundColor(.primary)
                                                        .textSelection(.enabled)
                                                
                                                HStack(spacing: 10) {
                                                        Button {
                                                                copyAddress()
                                                        } label: {
                                                                Label("复制", systemImage: "doc.on.doc")
                                                        }
                                                        .buttonStyle(.bordered)
                                                        
                                                        if let url = explorerURL {
                                                                Link(destination: url) {
                                                                        Label("浏览器查看", systemImage: "safari")
                                                                }
                                                                .buttonStyle(.bordered)
                                                        }
                                                }
                                        }
                                }
                                
                                Divider().opacity(0.6)
                                
                                InfoRow(title: "USDC 余额") {
                                        VStack(alignment: .leading, spacing: 6) {
                                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                        if isLoadingBalance {
                                                            ProgressView()
                                                                .scaleEffect(0.8)
                                                        }
                                                        Text(usdcBalanceDisplay)
                                                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                                        Text("USDC")
                                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                                .foregroundColor(.secondary)
                                                        
                                                        if !usdcBalanceSynced {
                                                                Text("未同步")
                                                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                                                        .foregroundColor(.secondary)
                                                                        .padding(.horizontal, 8)
                                                                        .padding(.vertical, 3)
                                                                        .background(
                                                                                Capsule().fill(Color.secondary.opacity(0.12))
                                                                        )
                                                        }
                                                }
                                                
                                                Button {
                                                        runBalanceRefresh()
                                                } label: {
                                                        Label("刷新余额", systemImage: "arrow.clockwise")
                                                }
                                                .buttonStyle(.bordered)
                                        }
                                }
                        }
                }
        }
        
        private var networkSelectorCard: some View {
            Card(title: "网络选择") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前网络：\(networkManager.currentNetwork.displayName)")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                        ForEach(NetworkManager.supportedNetworks) { network in
                            Button(action: {
                                networkManager.selectNetwork(network)
                                runBalanceRefresh()
                            }) {
                                Text(network.displayName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(network.name == networkManager.currentNetwork.name ? .white : .blue)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule()
                                            .fill(network.name == networkManager.currentNetwork.name ? Color.blue : Color.gray.opacity(0.2))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }

        
        private var x402Card: some View {
                Card(title: "x402（我们的优势）") {
                        VStack(alignment: .leading, spacing: 10) {
                                Text("MeshFlux 将使用 x402 协议让你用 USDC 完成支付/打赏等交互，并尽量做到用户侧\"无需 Gas\"的体验。")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                
                                Button {
                                        showX402Intro()
                                } label: {
                                        Label("了解 x402", systemImage: "sparkles")
                                }
                                .buttonStyle(.bordered)
                        }
                }
        }
        
        private var securityCard: some View {
                Card(title: "安全") {
                        VStack(spacing: 10) {
                                InfoRow(title: "PIN") {
                                        HStack(spacing: 8) {
                                                Image(systemName: hasPIN ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                                        .foregroundColor(hasPIN ? .green : .orange)
                                                Text(hasPIN ? "已设置" : "未设置")
                                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                                        .foregroundColor(.primary)
                                        }
                                }
                                
                                Text("我们不会展示助记词、派生路径等敏感/低价值信息。敏感操作（如签名/导出）再触发 PIN 校验。")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                        }
                }
        }
        
        private var resetCard: some View {
                Card(title: "调试 / 重置") {
                        Button {
                                confirmReset()
                        } label: {
                                HStack {
                                        Image(systemName: "trash")
                                        Text("清空钱包与 PIN")
                                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        Spacer()
                                }
                                .foregroundColor(.red)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                }
        }
        
        private var createWalletCard: some View {
                Card(title: "钱包") {
                        VStack(alignment: .leading, spacing: 12) {
                                Text("当前未检测到本地钱包或 PIN。")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                
                                Button {
                                        router.enterOnboarding()
                                } label: {
                                        Text("创建钱包")
                                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity, minHeight: 48)
                                                .background(
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                .fill(Color.blue)
                                                )
                                }
                                .buttonStyle(.plain)
                        }
                }
        }
        
        // MARK: - Data
        
        private func reload() {
                hasWallet = WalletStore.hasWallet()
                hasPIN = PINStore.hasPIN()
                
                guard let data = WalletStore.loadWalletBlob() else {
                        address = "—"
                        return
                }
                
                if let blob = try? JSONDecoder().decode(WalletBlobPreview.self, from: data),
                   let addr = blob.address, !addr.isEmpty {
                        address = addr
                } else {
                        address = "—"
                }
        }
        
        private func refreshUSDCBalance() async {
            guard scenePhase == .active else { return }
            guard address != "—" else {
                hud.showToast("请先创建或导入钱包")
                return
            }
            
            isLoadingBalance = true
            usdcBalanceSynced = false
            
            do {
                let balance = try await GoEngine.shared.getTokenBalance(
                    address: address,
                    tokenName: "USDC",
                    networkName: networkManager.currentNetwork.name
                )
                
                await MainActor.run {
                    if Task.isCancelled { return }
                    usdcBalanceDisplay = balance
                    usdcBalanceSynced = true
                    isLoadingBalance = false
                    if scenePhase == .active {
                        hud.showToast("余额已更新")
                    }
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled { return }
                    isLoadingBalance = false
                    usdcBalanceSynced = false
                    guard scenePhase == .active else { return }
                    hud.showAlert(
                        title: "查询余额失败",
                        message: error.localizedDescription,
                        primaryTitle: "确定",
                        tapToDismiss: true
                    )
                }
            }
        }

        private func triggerAutoRefreshIfNeeded(force: Bool) {
            guard isActiveTab, scenePhase == .active, hasWalletAndPIN else { return }
            if !force, let last = lastAutoRefreshAt, Date().timeIntervalSince(last) < 15 {
                return
            }
            lastAutoRefreshAt = Date()
            runBalanceRefresh()
        }

        private func runBalanceRefresh() {
            balanceRefreshTask?.cancel()
            balanceRefreshTask = Task {
                await refreshUSDCBalance()
            }
        }
        
        private var formattedAddress: String {
            // 确保地址始终以0x开头
            if address.hasPrefix("0x") {
                return address
            } else if address == "—" {
                return address
            } else {
                return "0x\(address)"
            }
        }
        
        private func copyAddress() {
                guard address != "—" else { return }
                UIPasteboard.general.string = formattedAddress
                hud.showToast("已复制地址")
        }
        
        private func showX402Intro() {
                hud.showAlert(
                        title: "x402 是什么？",
                        message: "简单说：它让 USDC 支付/打赏的交互更\"Web2 化\"。用户尽量不需要处理 Gas、复杂签名与链上细节，我们在体验上做封装。",
                        primaryTitle: "知道了",
                        tapToDismiss: true
                )
        }
        
        private func confirmReset() {
                hud.showAlert(
                        title: "确认清空？",
                        message: "将删除本机保存的钱包数据与 PIN。你需要助记词才能恢复。",
                        primaryTitle: "清空并重建",
                        secondaryTitle: "取消",
                        tapToDismiss: true,
                        showsCloseButton: true,
                        primaryAction: {
                                do {
                                        try WalletStore.clear()
                                        try PINStore.clear()
                                        hud.showToast("已清空")
                                        router.enterMain()
                                } catch {
                                        hud.showAlert(
                                                title: "清空失败",
                                                message: error.localizedDescription,
                                                primaryTitle: "确定",
                                                tapToDismiss: true
                                        )
                                }
                        }
                )
        }
        
        private var explorerURL: URL? {
                guard address != "—" else { return nil }
                // 根据当前网络设置决定浏览器URL
                let baseURL: String
                switch networkManager.currentNetwork.name {
                case "base-mainnet":
                    baseURL = "https://basescan.org/address/"
                case "base-testnet":
                    baseURL = "https://sepolia.basescan.org/address/"
                default:
                    baseURL = "https://basescan.org/address/"
                }
                return URL(string: "\(baseURL)\(address)")
        }
}

// 只取你需要展示的字段：address（不展示 createdAt / derivationPath）
private struct WalletBlobPreview: Decodable {
        let address: String?
}

// MARK: - Small UI

private struct Card<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content
        
        var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.primary)
                        
                        content
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                )
        }
}

private struct InfoRow<Right: View>: View {
        let title: String
        @ViewBuilder let right: Right
        
        var body: some View {
                HStack(alignment: .top, spacing: 12) {
                        Text(title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .leading)
                        
                        right
                        
                        Spacer(minLength: 0)
                }
        }
}
