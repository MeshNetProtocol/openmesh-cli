//
//  MnemonicDisplayView.swift
//  OpenMesh
//
//  Created by OpenMesh on 2026/1/8.
//

import SwiftUI

struct MnemonicDisplayView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase

    @State private var mnemonic: [String] = Self.makeDemoMnemonic()

    @State private var isRevealed: Bool = false
    @State private var confirmChecked: Bool = false

    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 顶部留出返回按钮空间
                    Color.clear.frame(height: 10)

                    header
                    securityCallouts
                    mnemonicCard

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 44)     // 给左上角返回按钮留空间（更像你截图）
                .padding(.bottom, 140) // 给底部固定栏留空间（防穿透）
            }

            // 顶部返回按钮（不依赖 toolbar，iOS15 更稳）
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
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("确定"))
            )
        }
        .onChange(of: scenePhase) { phase in
            // 进入后台自动隐藏助记词
            if phase != .active {
                isRevealed = false
                confirmChecked = false
            }
        }
    }

    // MARK: - Background (文档/安全页风格：与首页区分)

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
                Circle()
                    .fill(Color.white.opacity(0.85))
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

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Brand.brandBlue)
            }

            Text("备份助记词")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(Brand.title)

            Text("请按顺序抄写到离线介质，并妥善保管。\n助记词一旦泄露，你的钱包可能被直接控制。")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Brand.subTitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 6)
    }

    // MARK: - Security Callouts

    private var securityCallouts: some View {
        VStack(spacing: 10) {
            CalloutRow(
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                title: "不要截图 / 不要云端存储",
                detail: "截图可能被系统相册、云同步、第三方应用读取。"
            )
            CalloutRow(
                icon: "person.fill.xmark",
                iconColor: .red,
                title: "不要告诉任何人",
                detail: "任何人拿到助记词都能转走你的资产。"
            )
            CalloutRow(
                icon: "globe.asia.australia.fill",
                iconColor: Brand.brandBlue,
                title: "不要在任何网站输入",
                detail: "官方人员也不会索要助记词。"
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

    // MARK: - Mnemonic Card

    private var mnemonicCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Text("助记词")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(Brand.title)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        isRevealed.toggle()
                        if !isRevealed { confirmChecked = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        Text(isRevealed ? "隐藏" : "显示")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Brand.brandBlue))
                }
                .buttonStyle(.plain)
            }

            // ✅ 显示状态：2列，更易读；隐藏状态：3列，密度更高
            let cols = Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: isRevealed ? 2 : 3
            )

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(Array(mnemonic.enumerated()), id: \.offset) { idx, word in
                    mnemonicCell(index: idx + 1, word: word)
                }
            }
            .privacySensitive() // iOS15+ OK

            HStack(spacing: 10) {
                Button {
                    guard isRevealed else {
                        alertTitle = "请先显示助记词"
                        alertMessage = "为了安全，显示后才能复制。建议优先离线抄写。"
                        showingAlert = true
                        return
                    }
                    copyMnemonic()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("复制")
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Brand.brandBlue)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    regenerateMnemonic()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("重新生成")
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Brand.title)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.65))
                    )
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.25)

            Toggle(isOn: $confirmChecked) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我已离线抄写并安全保存")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(Brand.title)
                    Text("建议写在纸上或金属助记词板，避免拍照与云同步。")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Brand.subTitle)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Brand.brandBlue))
            .disabled(!isRevealed)
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

    private func mnemonicCell(index: Int, word: String) -> some View {
        let shownWord = isRevealed ? word : "•••••"

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
                .foregroundColor(Brand.title)
                .lineLimit(1)
                .minimumScaleFactor(0.78) // ✅ 减少 fe... eco... 的概率
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
        .animation(.easeInOut(duration: 0.15), value: isRevealed)
    }

    // MARK: - Bottom Action Bar (iOS15：用 Material + 覆盖到底部，防止“露底”)

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            Button {
                if !isRevealed {
                    alertTitle = "请先显示并抄写助记词"
                    alertMessage = "为了避免误操作，确认前需要先显示助记词。"
                    showingAlert = true
                    return
                }
                if !confirmChecked {
                    alertTitle = "还未确认备份"
                    alertMessage = "请勾选“我已离线抄写并安全保存”。"
                    showingAlert = true
                    return
                }

                alertTitle = "备份完成"
                alertMessage = "助记词已确认备份，请妥善保管。"
                showingAlert = true
            } label: {
                Text("已安全备份")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Brand.brandBlue)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 10)
            }
            .buttonStyle(.plain)

            Text("OpenMesh 不会上传或保存你的助记词。")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Brand.subTitle.opacity(0.90))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            // iOS15+ Material（更像你截图那种底部“卡片条”感觉）
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle().fill(Color.white.opacity(0.10))
                )
                .ignoresSafeArea(edges: .bottom) // ✅ 关键：覆盖到底部安全区，解决“露底”
        )
    }

    // MARK: - Actions

    private func copyMnemonic() {
        UIPasteboard.general.string = mnemonic.joined(separator: " ")
        alertTitle = "已复制到剪贴板"
        alertMessage = "出于安全考虑，建议复制后尽快清除剪贴板，并优先离线保存。"
        showingAlert = true
    }

    private func regenerateMnemonic() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
            mnemonic = Self.makeDemoMnemonic()
            isRevealed = false
            confirmChecked = false
        }
    }

    private static func makeDemoMnemonic() -> [String] {
        let pool = """
        gravity machine north sort system female filter attitude volume fold club stay feature office ecology stable narrow fog sponsor calm develop bridge
        """
            .split(separator: " ")
            .map(String.init)

        return Array(pool.shuffled().prefix(12))
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

struct MnemonicDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MnemonicDisplayView()
        }
    }
}
