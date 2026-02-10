import SwiftUI

// Centralized styling for the menu windows. Keep the palette aligned with mesh_logo:
// blue / light-blue / white, with subtle glass surfaces on top.
enum MeshFluxTheme {
    static let meshBlue = Color(red: 0.20, green: 0.58, blue: 0.98)
    static let meshCyan = Color(red: 0.35, green: 0.90, blue: 0.96)
    static let meshMint = Color(red: 0.27, green: 0.86, blue: 0.55)
    static let meshAmber = Color(red: 0.95, green: 0.74, blue: 0.22) // warm yellow/brown-ish

    // Tech/Futuristic Palette
    static let techDarkBlue = Color(red: 0.02, green: 0.05, blue: 0.12)
    static let techNeonBlue = Color(red: 0.00, green: 0.60, blue: 1.00)
    static let techNeonCyan = Color(red: 0.00, green: 1.00, blue: 0.95)
    static let techNeonGreen = Color(red: 0.00, green: 1.00, blue: 0.50)
    static let techNeonOrange = Color(red: 1.00, green: 0.55, blue: 0.00)

    static func windowBackground(_ scheme: ColorScheme) -> some ShapeStyle {
        // Dark but "blue" by default; light mode gets a soft sky gradient.
        if scheme == .light {
            return LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.98, blue: 1.00),
                    Color(red: 0.86, green: 0.94, blue: 1.00),
                    Color(red: 0.80, green: 0.90, blue: 0.99),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.10, blue: 0.18),
                Color(red: 0.06, green: 0.14, blue: 0.26),
                Color(red: 0.03, green: 0.08, blue: 0.14),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardFill(_ scheme: ColorScheme) -> some ShapeStyle {
        if scheme == .light {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.85),
                    Color(red: 0.96, green: 0.99, blue: 1.00).opacity(0.75),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(0.10),
                Color(red: 0.10, green: 0.20, blue: 0.34).opacity(0.22),
                Color.white.opacity(0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardStroke(_ scheme: ColorScheme) -> some ShapeStyle {
        if scheme == .light {
            return LinearGradient(
                colors: [
                    meshBlue.opacity(0.35),
                    Color.black.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                meshCyan.opacity(0.28),
                Color.white.opacity(0.10),
                meshBlue.opacity(0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // A futuristic glass card with a glowing border
    static func techCardBackground(scheme: ColorScheme, glowColor: Color = .clear) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(cardFill(scheme))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (glowColor == .clear ? meshCyan : glowColor).opacity(0.4),
                                Color.white.opacity(0.1),
                                (glowColor == .clear ? meshBlue : glowColor).opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: glowColor.opacity(scheme == .dark ? 0.15 : 0.05), radius: 8, x: 0, y: 4)
    }
}

struct MeshFluxWindowBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(MeshFluxTheme.windowBackground(scheme))
            .overlay {
                // Gentle highlight to avoid a flat background.
                RadialGradient(
                    colors: [
                        MeshFluxTheme.meshCyan.opacity(scheme == .light ? 0.15 : 0.18),
                        Color.clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
    }
}

struct MeshFluxCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(cornerRadius: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MeshFluxTheme.cardFill(scheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
                    }
            }
    }
}

struct MeshFluxTintButton: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let systemImage: String
    let tint: Color
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.8),
                                tint.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: tint.opacity(0.4), radius: 8, x: 0, y: 0)
        }
        .opacity(isBusy ? 0.8 : 1.0)
    }
}

