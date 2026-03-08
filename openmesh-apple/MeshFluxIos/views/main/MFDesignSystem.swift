import SwiftUI

enum MarketIOSTheme {
    static let meshBlue = Color(red: 0.17, green: 0.47, blue: 0.96)
    static let meshCyan = Color(red: 0.24, green: 0.78, blue: 0.95)
    static let meshMint = Color(red: 0.24, green: 0.82, blue: 0.60)
    static let meshAmber = Color(red: 0.96, green: 0.66, blue: 0.21)
    static let meshRed = Color(red: 0.92, green: 0.35, blue: 0.38)
    static let meshIndigo = Color(red: 0.29, green: 0.42, blue: 0.93)

    @ViewBuilder
    static func windowBackground(_ scheme: ColorScheme) -> some View {
        if scheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.10, blue: 0.18),
                    Color(red: 0.05, green: 0.16, blue: 0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.98, blue: 1.00),
                    Color(red: 0.87, green: 0.94, blue: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.86)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? meshBlue.opacity(0.38) : meshBlue.opacity(0.24)
    }

    static func chipFill(_ tint: Color, scheme: ColorScheme) -> Color {
        scheme == .dark ? tint.opacity(0.22) : tint.opacity(0.14)
    }

    static func chipStroke(_ tint: Color, scheme: ColorScheme) -> Color {
        scheme == .dark ? tint.opacity(0.52) : tint.opacity(0.28)
    }
}

struct MFHeaderBadge: Identifiable {
    let id = UUID()
    let title: String
    let tint: Color

    init(_ title: String, tint: Color = MarketIOSTheme.meshBlue) {
        self.title = title
        self.tint = tint
    }
}

struct MFHeaderSection: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    var badges: [MFHeaderBadge] = []
    var trailing: AnyView? = nil

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        badges: [MFHeaderBadge] = [],
        trailing: AnyView? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let eyebrow, !eyebrow.isEmpty {
                        Text(eyebrow)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(MarketIOSTheme.meshBlue.opacity(0.80))
                    }

                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                if let trailing {
                    trailing
                }
            }

            if !badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(badges) { badge in
                            MFStatusBadge(title: badge.title, tint: badge.tint)
                        }
                    }
                }
            }
        }
    }
}

struct MFGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let content: Content

    init(
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MarketIOSTheme.cardFill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.12 : 0.06), radius: 16, x: 0, y: 8)
    }
}

struct MFStatusBadge: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var tint: Color = MarketIOSTheme.meshBlue

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MarketIOSTheme.chipFill(tint, scheme: scheme))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(MarketIOSTheme.chipStroke(tint, scheme: scheme), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
            .foregroundStyle(.secondary)
    }
}

struct MFPrimaryButton<Label: View>: View {
    let action: () -> Void
    var isDisabled: Bool = false
    let label: Label

    init(
        isDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.isDisabled = isDisabled
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MarketIOSTheme.meshBlue, MarketIOSTheme.meshCyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }
}

struct MFSecondaryButton<Label: View>: View {
    @Environment(\.colorScheme) private var scheme
    let action: () -> Void
    var isDisabled: Bool = false
    let label: Label

    init(
        isDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.isDisabled = isDisabled
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MarketIOSTheme.cardFill(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
                )
                .foregroundStyle(MarketIOSTheme.meshBlue)
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }
}

struct MFDangerButton<Label: View>: View {
    @Environment(\.colorScheme) private var scheme
    let action: () -> Void
    var isDisabled: Bool = false
    let label: Label

    init(
        isDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.isDisabled = isDisabled
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MarketIOSTheme.chipFill(MarketIOSTheme.meshRed, scheme: scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MarketIOSTheme.meshRed.opacity(scheme == .dark ? 0.45 : 0.25), lineWidth: 1)
                )
                .foregroundStyle(MarketIOSTheme.meshRed)
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }
}

struct MFMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }
}

struct MarketIOSChip: View {
    let title: String
    var tint: Color = MarketIOSTheme.meshBlue

    var body: some View {
        MFStatusBadge(title: title, tint: tint)
    }
}

private struct MarketIOSCardModifier: ViewModifier {
    let horizontal: CGFloat
    let vertical: CGFloat

    func body(content: Content) -> some View {
        MFGlassCard(horizontalPadding: horizontal, verticalPadding: vertical) {
            content
        }
    }
}

extension View {
    func marketIOSCard(horizontal: CGFloat = 14, vertical: CGFloat = 12) -> some View {
        modifier(MarketIOSCardModifier(horizontal: horizontal, vertical: vertical))
    }

    @ViewBuilder
    func marketIOSListBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
