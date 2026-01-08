import SwiftUI

struct SetPINView: View {
    /// 控制“从助记词页 push 进来”的那条 NavigationLink
    @Binding var flowActive: Bool
    
    /// 12 words 用空格拼起来的字符串
    let mnemonic: String
    
    @State private var pin: String = ""
    @State private var confirmActive: Bool = false
    
    private let hud = AppHUD.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            pinFlowBackground
            
            NavigationLink(
                destination: ConfirmPINView(
                    flowActive: $flowActive,
                    confirmActive: $confirmActive,
                    firstPIN: $pin,
                    mnemonic: mnemonic
                ),
                isActive: $confirmActive
            ) { EmptyView() }
                .hidden()
            
            VStack(spacing: 18) {
                topBar(title: "设置解锁 PIN") { flowActive = false }
                
                VStack(spacing: 14) {
                    Text("设置解锁 PIN")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(Brand.title)
                    
                    Text("PIN 用于本地解锁 / 签名 / 查看助记词\n请勿告诉任何人")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Brand.subTitle)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 6)
                
                PinDotsInput(pin: $pin)
                    .padding(.top, 6)
                
                HStack {
                    Button {
                        pin = ""
                        hud.showToast("已清除")
                    } label: {
                        Text("清除")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Brand.brandBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Brand.brandBlue.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal, 22)
                
                Spacer()
                
                Button {
                    guard pin.count == 6 else {
                        hud.showToast("请输入 6 位数字 PIN")
                        return
                    }
                    confirmActive = true
                } label: {
                    Text("继续")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(pin.count == 6 ? Brand.brandBlue : Brand.brandBlue.opacity(0.55))
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(pin.count != 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: scenePhase) { phase in
            if phase != .active { pin = "" }
        }
    }
}

struct ConfirmPINView: View {
    @Binding var flowActive: Bool
    @Binding var confirmActive: Bool
    @Binding var firstPIN: String
    
    let mnemonic: String
    
    @State private var pin2: String = ""
    
    private let hud = AppHUD.shared
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var router: AppRouter
    
    var body: some View {
        ZStack {
            pinFlowBackground
            
            VStack(spacing: 18) {
                topBar(title: "确认 PIN") { confirmActive = false }
                
                VStack(spacing: 14) {
                    Text("确认 PIN")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(Brand.title)
                    
                    Text("请再次输入 6 位数字")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Brand.subTitle)
                }
                .padding(.top, 6)
                
                PinDotsInput(pin: $pin2)
                    .padding(.top, 6)
                
                Spacer()
                
                Button {
                    guard pin2.count == 6 else {
                        hud.showToast("请输入 6 位数字 PIN")
                        return
                    }
                    guard pin2 == firstPIN else {
                        hud.showToast("两次 PIN 不一致，请重试")
                        firstPIN = ""
                        pin2 = ""
                        confirmActive = false
                        return
                    }
                    
                    Task { await persistWalletAndFinish() }
                } label: {
                    Text("完成")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(pin2.count == 6 ? Brand.brandBlue : Brand.brandBlue.opacity(0.55))
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(pin2.count != 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: scenePhase) { phase in
            if phase != .active { pin2 = "" }
        }
    }
    
    private func persistWalletAndFinish() async {
        // Swift 6 默认 MainActor 隔离时：别用 Task.detached 去调这些 static 方法
        hud.showLoading("正在创建钱包…")
        
        do {
            let pin = firstPIN
            
            // 1) 先让 Go 构建 EVM/BIP44 钱包，并返回 JSON（内含已用 PIN 加密的 secrets envelope）
            let walletJSON = try await GoEngine.shared.createEvmWallet(mnemonic: mnemonic, pin: pin)
            
            // 2) 保存 Go 的结果（不再二次加密）
            try WalletStore.saveWalletBlob(Data(walletJSON.utf8))
            
            // 3) 保存 PIN 校验材料（用于后续本地解锁校验）
            try PINStore.savePIN(pin)
            
            hud.hideLoading()
            hud.showToast("钱包已创建")
            router.enterMain()
            flowActive = false
        } catch {
            hud.hideLoading()
            hud.showAlert(title: "创建失败", message: error.localizedDescription, tapToDismiss: true)
        }
    }
}

// MARK: - PIN Dots Input (保持你原来的)

private struct PinDotsInput: View {
    @Binding var pin: String
    @FocusState private var focused: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { idx in
                    Circle()
                        .fill(idx < pin.count ? Brand.brandBlue : Color.black.opacity(0.12))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.60), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 12)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .privacySensitive()
            
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: pin) { newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    let clipped = String(filtered.prefix(6))
                    if clipped != pin { pin = clipped }
                }
        }
        .padding(.horizontal, 20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
        }
    }
}

// MARK: - Shared UI（保持你原来的）

private func topBar(title: String, onBack: @escaping () -> Void) -> some View {
    HStack {
        Button(action: onBack) {
            ZStack {
                Circle().fill(Color.white.opacity(0.85))
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Brand.ink)
            }
            .frame(width: 36, height: 36)
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        
        Spacer()
        
        Text(title)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(Brand.ink.opacity(0.88))
        
        Spacer()
        
        Color.clear.frame(width: 36, height: 36)
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
}

private var pinFlowBackground: some View {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        
        LinearGradient(
            colors: [Brand.sky.opacity(0.95), Brand.mid.opacity(0.55), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

private enum Brand {
    static let sky = Color(red: 0.62, green: 0.82, blue: 1.00)
    static let mid = Color(red: 0.29, green: 0.60, blue: 1.00)
    static let brandBlue = Color(red: 0.10, green: 0.39, blue: 0.95)
    
    static let title = Color(red: 0.08, green: 0.12, blue: 0.20)
    static let subTitle = Color(red: 0.35, green: 0.42, blue: 0.52)
    static let ink = Color(red: 0.12, green: 0.18, blue: 0.28)
}
