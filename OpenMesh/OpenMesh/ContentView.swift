//
//  ContentView.swift
//  OpenMesh
//
//  Created by wesley on 2026/1/8.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            // Background: match your logo's soft sky-blue → deep blue feeling
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.62, green: 0.82, blue: 1.00), // light sky
                    Color(red: 0.29, green: 0.60, blue: 1.00), // mid blue
                    Color(red: 0.10, green: 0.39, blue: 0.95)  // deep blue
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft wave / blob highlights (subtle, like your logo background shapes)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.00)
                            ]),
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 220
                        )
                    )
                    .frame(width: 380, height: 380)
                    .offset(x: -140, y: -240)

                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.00)
                            ]),
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 260
                        )
                    )
                    .frame(width: 520, height: 520)
                    .offset(x: 180, y: 260)
            }
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 26)

                // Logo hero
                VStack(spacing: 14) {
                    ZStack {
                        // Soft “badge” behind logo
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 124, height: 124)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
                            )

                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 92, height: 92)
                            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
                    }

                    Text("OpenMesh")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Secure • Lightweight • P2P")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.88))
                }
                .padding(.top, 8)

                Spacer(minLength: 10)

                // Card container (glass style)
                VStack(spacing: 14) {
                    PrimaryActionButton(title: "创建新钱包") {
                        // TODO: push to RN wallet screen (create)
                    }

                    SecondaryActionButton(title: "导入助记词") {
                        // TODO: push to RN wallet screen (import)
                    }

                    // Small hint row
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.85))

                        Text("密钥默认保存在设备安全区")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    .padding(.top, 4)
                }
                .padding(18)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)
                .padding(.horizontal, 22)

                Spacer()

                // Footer
                Text("By continuing, you agree to the Terms & Privacy Policy")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.70))
                    .padding(.bottom, 18)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
        }
    }
}

// MARK: - Buttons

private struct PrimaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color(red: 0.10, green: 0.39, blue: 0.95))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
