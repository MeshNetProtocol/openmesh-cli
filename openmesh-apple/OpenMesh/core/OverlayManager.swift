//
//  OverlayManager.swift
//  MeshFlux
//
//  Bottom-sheet style alert + Loading + Toast
//  iOS 15+ compatible
//

import SwiftUI
import Combine

// MARK: - HUD Manager

@MainActor
final class AppHUD: ObservableObject {
    static let shared = AppHUD()
    
    struct AlertModel: Identifiable, Equatable {
        let id = UUID()
        
        var title: String
        var message: String
        
        var primaryTitle: String = "确定"
        var secondaryTitle: String? = nil
        
        var primaryAction: (() -> Void)? = nil
        var secondaryAction: (() -> Void)? = nil
        
        /// 点击遮罩是否允许关闭（默认 false 更安全）
        var tapToDismiss: Bool = false
        
        /// 是否显示右上角关闭按钮
        var showsCloseButton: Bool = true
        
        static func == (lhs: AlertModel, rhs: AlertModel) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    @Published var alert: AlertModel? = nil
    @Published var isLoading: Bool = false
    @Published var loadingText: String? = nil
    @Published var toast: String? = nil
    
    private init() {}
    
    func showAlert(
        title: String,
        message: String,
        primaryTitle: String = "确定",
        secondaryTitle: String? = nil,
        tapToDismiss: Bool = false,
        showsCloseButton: Bool = true,
        primaryAction: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        alert = AlertModel(
            title: title,
            message: message,
            primaryTitle: primaryTitle,
            secondaryTitle: secondaryTitle,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            tapToDismiss: tapToDismiss,
            showsCloseButton: showsCloseButton
        )
    }
    
    func dismissAlert() {
        alert = nil
    }
    
    func showLoading(_ text: String? = nil) {
        loadingText = text
        isLoading = true
    }
    
    func hideLoading() {
        isLoading = false
        loadingText = nil
    }
    
    func showToast(_ text: String, duration: TimeInterval = 1.4) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self.toast == text { self.toast = nil }
        }
    }
}

// MARK: - Global Overlay

struct AppHUDOverlay: View {
    @ObservedObject var hud: AppHUD
    
    var body: some View {
        ZStack {
            // 1) Loading
            if hud.isLoading {
                loadingLayer
                    .transition(.opacity)
                    .zIndex(30)
            }
            
            // 2) Alert Bottom Sheet
            if let model = hud.alert {
                alertLayer(model: model)
                    .transition(.opacity)
                    .zIndex(40)
            }
            
            // 3) Toast
            if let toast = hud.toast {
                toastLayer(text: toast)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: hud.isLoading)
        .animation(.easeOut(duration: 0.20), value: hud.alert?.id)
        .animation(.easeOut(duration: 0.18), value: hud.toast)
    }
    
    // MARK: - Loading
    
    private var loadingLayer: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.06)
                
                if let t = hud.loadingText, !t.isEmpty {
                    Text(t)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.78))
            )
            .shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 12)
        }
    }
    
    // MARK: - Alert Bottom Sheet
    
    private func alertLayer(model: AppHUD.AlertModel) -> some View {
        ZStack(alignment: .bottom) {
            // 背景遮罩
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    if model.tapToDismiss {
                        hud.dismissAlert()
                    }
                }
            
            // 底部卡片
            BottomSheetCard(model: model) {
                hud.dismissAlert()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Toast
    
    private func toastLayer(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(Color.black.opacity(0.78))
                )
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 10)
                .padding(.bottom, 24)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Bottom Sheet Card View

private struct BottomSheetCard: View {
    let model: AppHUD.AlertModel
    let onDismiss: () -> Void
    
    // iOS15：手势拖拽下拉关闭（可选），这里默认启用
    @State private var dragY: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // 顶部手柄 + 关闭按钮
            HStack(alignment: .center) {
                Capsule()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 44, height: 5)
                    .padding(.leading, 8)
                
                Spacer()
                
                if model.showsCloseButton {
                    Button {
                        onDismiss()
                    } label: {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.06))
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Brand.ink.opacity(0.75))
                        }
                        .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            
            // 标题 / 文案
            VStack(spacing: 8) {
                Text(model.title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Brand.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(model.message)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Brand.subTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider().opacity(0.18)
            
            // 按钮区（单按钮：全宽；双按钮：左右）
            if let secondary = model.secondaryTitle {
                HStack(spacing: 10) {
                    Button {
                        onDismiss()
                        model.secondaryAction?()
                    } label: {
                        Text(secondary)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Brand.brandBlue)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Brand.brandBlue.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        onDismiss()
                        model.primaryAction?()
                    } label: {
                        Text(model.primaryTitle)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Brand.brandBlue)
                            )
                            .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    onDismiss()
                    model.primaryAction?()
                } label: {
                    Text(model.primaryTitle)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Brand.brandBlue)
                        )
                        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(sheetBackground)
        .offset(y: max(0, dragY))
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    // 只允许向下拖
                    if v.translation.height > 0 {
                        dragY = v.translation.height
                    }
                }
                .onEnded { v in
                    let shouldDismiss = v.translation.height > 90
                    withAnimation(.easeOut(duration: 0.18)) {
                        dragY = 0
                    }
                    if shouldDismiss && model.tapToDismiss {
                        // 只有允许“点击遮罩关闭”的弹窗，才允许下拉关闭
                        onDismiss()
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
    
    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial) // iOS15+ OK
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.75))
            )
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 16)
    }
}

// MARK: - Brand Palette (keep consistent with your app)

private enum Brand {
    static let brandBlue = Color(red: 0.10, green: 0.39, blue: 0.95)
    
    static let title = Color(red: 0.08, green: 0.12, blue: 0.20)
    static let subTitle = Color(red: 0.35, green: 0.42, blue: 0.52)
    static let ink = Color(red: 0.12, green: 0.18, blue: 0.28)
}
