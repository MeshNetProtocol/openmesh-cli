//
//  ImportMnemonicView.swift
//  MeshFlux
//
//  iOS 15+ SwiftUI
//  Import mnemonic -> confirm risk -> SetPINView -> ConfirmPINView (persist via GoEngine)
//

import SwiftUI

struct ImportMnemonicView: View {
        @Environment(\.presentationMode) private var presentationMode
        @Environment(\.scenePhase) private var scenePhase
        
        @State private var mnemonicText: String = ""
        @State private var consentChecked: Bool = false
        @State private var showPinFlow: Bool = false
        @FocusState private var phraseFocused: Bool

        private let hud = AppHUD.shared
        
        private var normalizedWords: [String] {
                parseWords(mnemonicText)
        }
        
        private var normalizedMnemonic: String {
                normalizedWords.prefix(12).joined(separator: " ")
        }
        
        var body: some View {
                ZStack {
                        background
                        
                        NavigationLink(
                                destination: SetPINView(
                                        flowActive: $showPinFlow,
                                        mnemonic: normalizedMnemonic
                                ),
                                isActive: $showPinFlow
                        ) { EmptyView() }
                                .hidden()
                        
                        ScrollView(showsIndicators: false) {
                                VStack(spacing: 16) {
                                        Color.clear.frame(height: 10)
                                        header
                                        riskCallouts
                                        inputCard
                                        previewCard
                                        
                                        Spacer(minLength: 10)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 44)
                                .padding(.bottom, 140)
                        }.onTapGesture { phraseFocused = false }.toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("完成") { phraseFocused = false }
                                }
                            }

                        
                        VStack {
                                HStack {
                                        backButton
                                        Spacer()
                                }
                                .padding(.leading, 16)
                                .padding(.top, 10)
                                Spacer()
                        }
                }
                .navigationBarBackButtonHidden(true)
                .safeAreaInset(edge: .bottom) {
                        bottomActionBar
                }
                .onChange(of: scenePhase) { phase in
                        if phase != .active {
                                // 高风险：进入后台时清空输入（配合 privacySensitive）
                                mnemonicText = ""
                                consentChecked = false
                        }
                }
        }
        
        // MARK: - Background
        
        private var background: some View {
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
                        
                        VStack(spacing: 0) {
                                Spacer()
                                WaveShape(amplitude: 10, baseline: 0.55)
                                        .fill(Brand.mid.opacity(0.10))
                                        .frame(height: 160)
                        }
                        .ignoresSafeArea()
                }
        }
        
        // MARK: - Back Button
        
        private var backButton: some View {
                Button {
                        presentationMode.wrappedValue.dismiss()
                } label: {
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
        }
        
        // MARK: - Header
        
        private var header: some View {
                VStack(spacing: 10) {
                        ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white.opacity(0.88))
                                        .frame(width: 52, height: 52)
                                        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 8)
                                
                                Image(systemName: "tray.and.arrow.down.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(Brand.brandBlue)
                        }
                        
                        Text("导入助记词")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundColor(Brand.title)
                        
                        Text("粘贴或输入 12 个英文单词。\n导入仅在本地创建钱包并加密保存，不会上云。")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Brand.subTitle)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                }
                .padding(.top, 6)
        }
        
        // MARK: - Risk Callouts
        
        private var riskCallouts: some View {
                VStack(spacing: 10) {
                        CalloutRow(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .orange,
                                title: "不要在不可信来源导入",
                                detail: "钓鱼网站/截图/云端备忘录都可能泄露助记词。"
                        )
                        CalloutRow(
                                icon: "lock.shield.fill",
                                iconColor: Brand.brandBlue,
                                title: "本地加密保存",
                                detail: "导入后会用你设置的 6 位 PIN 在本地加密钱包数据。"
                        )
                        CalloutRow(
                                icon: "person.fill.xmark",
                                iconColor: .red,
                                title: "任何人都不该索要助记词",
                                detail: "官方人员也不会向你索取助记词。"
                        )
                }
                .padding(14)
                .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                                .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(Color.white.opacity(0.60), lineWidth: 1)
                                )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 10)
        }
        
        // MARK: - Input Card
        
        private var inputCard: some View {
                VStack(spacing: 12) {
                        HStack {
                                Text("输入助记词")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundColor(Brand.title)
                                
                                Spacer()
                                
                                Text("\(min(normalizedWords.count, 12))/12")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(normalizedWords.count == 12 ? Brand.brandBlue : Brand.subTitle)
                        }
                        
                        ZStack(alignment: .topLeading) {
                                TextEditor(text: $mnemonicText).focused($phraseFocused)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(Brand.title)
                                        .frame(minHeight: 110)
                                        .padding(10)
                                        .background(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .fill(Color.white)
                                                        .overlay(
                                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                                        )
                                        )
                                        .textInputAutocapitalization(.never)
                                        .disableAutocorrection(true)
                                        .privacySensitive()
                                
                                if mnemonicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("在此粘贴：word1 word2 ... word12")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(Brand.subTitle.opacity(0.65))
                                                .padding(.horizontal, 18)
                                                .padding(.vertical, 18)
                                                .allowsHitTesting(false)
                                }
                        }
                        
                        HStack(spacing: 10) {
                                Button {
                                        let clip = UIPasteboard.general.string ?? ""
                                        if clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                hud.showToast("剪贴板为空")
                                                return
                                        }
                                        mnemonicText = clip
                                        hud.showToast("已粘贴")
                                        phraseFocused = false

                                } label: {
                                        HStack(spacing: 8) {
                                                Image(systemName: "doc.on.clipboard")
                                                Text("粘贴")
                                        }
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(Brand.brandBlue)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .fill(Brand.brandBlue.opacity(0.10))
                                        )
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                        mnemonicText = ""
                                        consentChecked = false
                                        hud.showToast("已清空")
                                } label: {
                                        HStack(spacing: 8) {
                                                Image(systemName: "xmark.circle.fill")
                                                Text("清空")
                                        }
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(Brand.title)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .fill(Color.white.opacity(0.70))
                                        )
                                }
                                .buttonStyle(.plain)
                        }
                        
                        Toggle(isOn: $consentChecked) {
                                VStack(alignment: .leading, spacing: 2) {
                                        Text("我理解导入存在风险")
                                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                                .foregroundColor(Brand.title)
                                        Text("我确认助记词来自可信离线来源，并自行承担风险。")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundColor(Brand.subTitle)
                                }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Brand.brandBlue))
                }
                .padding(16)
                .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.86))
                                .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .stroke(Color.white.opacity(0.60), lineWidth: 1)
                                )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 12)
        }
        
        // MARK: - Preview Card (12 slots)
        
        private var previewCard: some View {
                VStack(spacing: 12) {
                        HStack {
                                Text("预览（按顺序）")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundColor(Brand.title)
                                Spacer()
                                
                                if normalizedWords.count > 12 {
                                        Text("检测到多于 12 个词")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(.orange)
                                }
                        }
                        
                        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
                        LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(0..<12, id: \.self) { idx in
                                        let w: String? = (idx < normalizedWords.count) ? normalizedWords[idx] : nil
                                        previewCell(index: idx + 1, word: w)
                                }
                        }
                        .privacySensitive()
                        
                        if normalizedWords.count == 12 {
                                Button {
                                        // 一键格式化：把输入整理成标准空格分隔（便于减少奇怪分隔符导致的误差）
                                        mnemonicText = normalizedMnemonic
                                        hud.showToast("已格式化")
                                } label: {
                                        HStack(spacing: 8) {
                                                Image(systemName: "wand.and.stars")
                                                Text("格式化为标准空格分隔")
                                        }
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Brand.brandBlue)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .fill(Color.white)
                                        )
                                }
                                .buttonStyle(.plain)
                        }
                }
                .padding(16)
                .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.86))
                                .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .stroke(Color.white.opacity(0.60), lineWidth: 1)
                                )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 12)
        }
        
        private func previewCell(index: Int, word: String?) -> some View {
                let isPlaceholder = (word == nil || word?.isEmpty == true)
                let shownWord = isPlaceholder ? "—" : (word ?? "")
                
                return HStack(spacing: 8) {
                        ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Brand.brandBlue.opacity(0.12))
                                Text("\(index)")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundColor(Brand.brandBlue)
                        }
                        .frame(width: 28, height: 28)
                        
                        Text(shownWord)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(Brand.title.opacity(isPlaceholder ? 0.55 : 1.0))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .truncationMode(.tail)
                        
                        Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white)
                                .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                )
                )
                .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 6)
        }
        
        // MARK: - Bottom Action Bar
        
        private var bottomActionBar: some View {
                VStack(spacing: 10) {
                        Button {
                                handleContinue()
                        } label: {
                                Text("继续设置 PIN")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .background(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .fill(canContinue ? Brand.brandBlue : Brand.brandBlue.opacity(0.55))
                                        )
                                        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canContinue)
                        
                        Text("MeshFlux 不会上传你的助记词，仅在本地加密保存。")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Brand.subTitle.opacity(0.90))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .background(
                        Rectangle()
                                .fill(.ultraThinMaterial)
                                .overlay(Rectangle().fill(Color.white.opacity(0.10)))
                                .ignoresSafeArea(edges: .bottom)
                )
        }
        
        private var canContinue: Bool {
                normalizedWords.count == 12 && consentChecked
        }
        
        private func handleContinue() {
                if normalizedWords.isEmpty {
                        hud.showToast("请输入或粘贴助记词")
                        return
                }
                if normalizedWords.count != 12 {
                        hud.showAlert(
                                title: "助记词数量不正确",
                                message: "期望 12 个单词，但检测到 \(normalizedWords.count) 个。请检查空格/换行分隔。",
                                tapToDismiss: true
                        )
                        return
                }
                if !consentChecked {
                        hud.showToast("请先勾选风险确认")
                        return
                }
                
                hud.showAlert(
                        title: "确认导入助记词？",
                        message: "导入助记词属于高风险操作。\n\nMeshFlux 不会上传助记词，将在本机使用你设置的 PIN 加密保存钱包数据。\n\n请确认当前环境安全（无录屏、无投屏、无第三方键盘）。",
                        primaryTitle: "继续",
                        secondaryTitle: "取消",
                        tapToDismiss: false,
                        primaryAction: {
                                showPinFlow = true
                        },
                        secondaryAction: nil
                )
        }
        
        // MARK: - Parsing
        
        private func parseWords(_ text: String) -> [String] {
                // 只保留 a-z，其余都当分隔符（避免逗号/中文空格等导致 Go 校验失败）
                let lower = text.lowercased()
                var cleaned = ""
                cleaned.reserveCapacity(lower.count)
                for ch in lower {
                        if ch >= "a" && ch <= "z" {
                                cleaned.append(ch)
                        } else {
                                cleaned.append(" ")
                        }
                }
                
                return cleaned
                        .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                        .map { String($0) }
                        .filter { !$0.isEmpty }
        }
}

// MARK: - Small Components

private struct CalloutRow: View {
        let icon: String
        let iconColor: Color
        let title: String
        let detail: String
        
        var body: some View {
                HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(iconColor)
                                .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundColor(Brand.title)
                                
                                Text(detail)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(Brand.subTitle)
                        }
                        
                        Spacer(minLength: 0)
                }
        }
}

private struct WaveShape: Shape {
        var amplitude: CGFloat
        var baseline: CGFloat
        
        func path(in rect: CGRect) -> Path {
                var p = Path()
                let h = rect.height
                let w = rect.width
                let y = h * baseline
                
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: y))
                
                p.addCurve(
                        to: CGPoint(x: w * 0.5, y: y + amplitude),
                        control1: CGPoint(x: w * 0.20, y: y - amplitude),
                        control2: CGPoint(x: w * 0.32, y: y + amplitude * 1.2)
                )
                p.addCurve(
                        to: CGPoint(x: w, y: y),
                        control1: CGPoint(x: w * 0.68, y: y + amplitude * 0.7),
                        control2: CGPoint(x: w * 0.86, y: y - amplitude)
                )
                
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
                return p
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
