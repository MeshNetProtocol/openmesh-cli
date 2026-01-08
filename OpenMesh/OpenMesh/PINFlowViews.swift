//
//  PINFlowViews.swift
//  OpenMesh
//
//  Set PIN (6 digits) -> Confirm PIN
//  iOS 15+
//

import SwiftUI

struct SetPINView: View {
    /// 控制“从助记词页 push 进来”的那条 NavigationLink
    @Binding var flowActive: Bool
    
    @State private var pin: String = ""
    @State private var confirmActive: Bool = false
    
    private let hud = AppHUD.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            pinFlowBackground
            
            // programmatic push to Confirm
            NavigationLink(
                destination: ConfirmPINView(
                    flowActive: $flowActive,
                    confirmActive: $confirmActive,
                    firstPIN: $pin
                ),
                isActive: $confirmActive
            ) { EmptyView() }
                .hidden()
            
            VStack(spacing: 18) {
                topBar(title: "设置解锁 PIN") {
                    flowActive = false
                }
                
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
            if phase != .active {
                // 进入后台清空
                pin = ""
            }
        }
    }
}

struct ConfirmPINView: View {
    @Binding var flowActive: Bool
    @Binding var confirmActive: Bool
    @Binding var firstPIN: String
    
    @State private var pin2: String = ""
    
    private let hud = AppHUD.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            pinFlowBackground
            
            VStack(spacing: 18) {
                topBar(title: "确认 PIN") {
                    // back to Set
                    confirmActive = false
                }
                
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
                        hud.showAlert(
                            title: "两次 PIN 不一致",
                            message: "请重新设置 PIN。",
                            primaryTitle: "重新输入",
                            tapToDismiss: true
                        )
                        // 清空并回到 SetPINView
                        firstPIN = ""
                        pin2 = ""
                        confirmActive = false
                        return
                    }
                    
                    Task { await persistPINAndFinish() }
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
            if phase != .active {
                pin2 = ""
            }
        }
    }
    
    private func persistPINAndFinish() async {
        await MainActor.run {
            hud.showLoading("正在保存 PIN…")
        }
        
        do {
            try PINStore.savePIN(firstPIN)
            await MainActor.run {
                hud.hideLoading()
                hud.showToast("PIN 已设置")
                // 退出整个 PIN 流程（回到助记词页）
                flowActive = false
            }
        } catch {
            await MainActor.run {
                hud.hideLoading()
                hud.showAlert(
                    title: "保存失败",
                    message: error.localizedDescription,
                    tapToDismiss: true
                )
            }
        }
    }
}

// MARK: - PIN Dots Input

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
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.55), lineWidth: 1)
                        )
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
            
            // hidden input
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode) // iOS15 里更“顺手”的数字输入
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: pin) { newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    let clipped = String(filtered.prefix(6))
                    if clipped != pin {
                        pin = clipped
                    }
                }
        }
        .padding(.horizontal, 20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focused = true
            }
        }
    }
}

// MARK: - Shared UI

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
        .accessibilityLabel("返回")
        
        Spacer()
        
        Text(title)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(Brand.ink.opacity(0.88))
        
        Spacer()
        
        // keep balance
        Color.clear.frame(width: 36, height: 36)
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
}

private var pinFlowBackground: some View {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
        
        LinearGradient(
            colors: [
                Brand.sky.opacity(0.95),
                Brand.mid.opacity(0.55),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

// MARK: - Brand (file-private)

private enum Brand {
    static let sky = Color(red: 0.62, green: 0.82, blue: 1.00)
    static let mid = Color(red: 0.29, green: 0.60, blue: 1.00)
    static let brandBlue = Color(red: 0.10, green: 0.39, blue: 0.95)
    
    static let title = Color(red: 0.08, green: 0.12, blue: 0.20)
    static let subTitle = Color(red: 0.35, green: 0.42, blue: 0.52)
    static let ink = Color(red: 0.12, green: 0.18, blue: 0.28)
}
