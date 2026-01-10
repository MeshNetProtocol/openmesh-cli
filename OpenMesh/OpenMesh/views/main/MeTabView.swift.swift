import SwiftUI
import UIKit

struct MeTabView: View {
        @EnvironmentObject private var router: AppRouter
        private let hud = AppHUD.shared
        
        @AppStorage("openmesh.usdc_balance_display") private var usdcBalanceDisplay: String = "0.00"
        @AppStorage("openmesh.usdc_balance_synced") private var usdcBalanceSynced: Bool = false
        
        @State private var address: String = "—"
        @State private var hasPIN: Bool = false
        
        var body: some View {
                ScrollView {
                        VStack(spacing: 14) {
                                walletCard
                                x402Card
                                securityCard
                                resetCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
                .navigationTitle("我的")
                .onAppear { reload() }
        }
        
        // MARK: - Cards
        
        private var walletCard: some View {
                Card(title: "钱包") {
                        VStack(spacing: 10) {
                                InfoRow(title: "钱包地址") {
                                        VStack(alignment: .leading, spacing: 6) {
                                                Text(address)
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
                                                        refreshUSDCBalance()
                                                } label: {
                                                        Label("刷新余额", systemImage: "arrow.clockwise")
                                                }
                                                .buttonStyle(.bordered)
                                        }
                                }
                        }
                }
        }
        
        private var x402Card: some View {
                Card(title: "x402（我们的优势）") {
                        VStack(alignment: .leading, spacing: 10) {
                                Text("OpenMesh 将使用 x402 协议让你用 USDC 完成支付/打赏等交互，并尽量做到用户侧“无需 Gas”的体验。")
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
                                        Text("清空钱包与 PIN，回到新手流程")
                                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        Spacer()
                                }
                                .foregroundColor(.red)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                }
        }
        
        // MARK: - Data
        
        private func reload() {
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
        
        private func refreshUSDCBalance() {
                // 这里先保留 UI/状态位，后续你接入“链上余额查询 / x402 账户系统”时把真实余额写入 usdcBalanceDisplay 即可
                usdcBalanceSynced = false
                hud.showToast("余额同步逻辑待接入")
        }
        
        private func copyAddress() {
                guard address != "—" else { return }
                UIPasteboard.general.string = address
                hud.showToast("已复制地址")
        }
        
        private func showX402Intro() {
                hud.showAlert(
                        title: "x402 是什么？",
                        message: "简单说：它让 USDC 支付/打赏的交互更“Web2 化”。用户尽量不需要处理 Gas、复杂签名与链上细节，我们在体验上做封装。",
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
                                        router.enterOnboarding()
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
                return URL(string: "https://basescan.org/address/\(address)")
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
