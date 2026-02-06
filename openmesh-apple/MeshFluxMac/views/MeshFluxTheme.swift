import SwiftUI

// Centralized styling for the menu windows. Keep the palette aligned with mesh_logo:
// blue / light-blue / white, with subtle glass surfaces on top.
enum MeshFluxTheme {
    static let meshBlue = Color(red: 0.20, green: 0.58, blue: 0.98)
    static let meshCyan = Color(red: 0.35, green: 0.90, blue: 0.96)
    static let meshMint = Color(red: 0.27, green: 0.86, blue: 0.55)
    static let meshAmber = Color(red: 0.95, green: 0.74, blue: 0.22) // warm yellow/brown-ish

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
                    .scaleEffect(0.85)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(scheme == .light ? Color.white : Color.white.opacity(0.95))
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(scheme == .light ? 0.95 : 0.90),
                            tint.opacity(scheme == .light ? 0.78 : 0.70),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(scheme == .light ? 0.20 : 0.14), lineWidth: 1)
                }
                .shadow(color: tint.opacity(0.25), radius: 10, x: 0, y: 6)
        }
    }
}

