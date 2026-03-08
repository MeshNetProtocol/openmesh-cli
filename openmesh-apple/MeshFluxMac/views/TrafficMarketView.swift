import SwiftUI
import AppKit
import VPNLibrary

struct TrafficMarketView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var vpnController: VPNController
    @State private var providers: [TrafficProvider] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var installingId: String?
    @State private var installedProviderIDs: Set<String> = []
    @State private var installedPackageHashByProvider: [String: String] = [:]
    @State private var pendingRuleSetsByProvider: [String: [String]] = [:]

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(MeshFluxTheme.meshBlue)
                        Text("正在加载供应商…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(MeshFluxTheme.meshAmber)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        Button("重试") {
                            Task { await loadData() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MeshFluxTheme.meshBlue)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if providers.isEmpty {
                                Text("暂无推荐供应商")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            }
                            ForEach(providers) { provider in
                                ProviderCard(
                                    provider: provider,
                                    isInstalling: installingId == provider.id,
                                    actionStyle: actionStyle(for: provider),
                                    showInitBadge: needsInitialization(provider: provider)
                                ) {
                                    ProviderInstallWindowManager.shared.show(provider: provider) { isInstalling in
                                        installingId = isInstalling ? provider.id : nil
                                        if !isInstalling {
                                            Task { await reloadInstalledState() }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectedProfileDidChange)) { _ in
            Task { await reloadInstalledState() }
        }
    }

    private var headerBar: some View {
        MarketSectionHeader(
            onOpenMarket: {
                ProviderMarketWindowManager.shared.show(vpnController: vpnController)
            },
            onOpenImport: {
                OfflineImportWindowManager.shared.show(onInstalled: {
                    Task { await reloadInstalledState() }
                })
            }
        )
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        providers = (try? await MarketService.shared.fetchMarketRecommendedCached()) ?? []
        await reloadInstalledState()
        isLoading = false
    }

    private func reloadInstalledState() async {
        let byProfile = await SharedPreferences.installedProviderIDByProfile.get()
        installedProviderIDs = Set(byProfile.values)
        installedPackageHashByProvider = await SharedPreferences.installedProviderPackageHash.get()
        pendingRuleSetsByProvider = await SharedPreferences.installedProviderPendingRuleSetTags.get()
    }

    private func isInstalled(provider: TrafficProvider) -> Bool {
        installedProviderIDs.contains(provider.id)
    }

    private func isUpdateAvailable(provider: TrafficProvider) -> Bool {
        guard isInstalled(provider: provider) else { return false }
        guard let remoteHash = provider.package_hash, !remoteHash.isEmpty else { return false }
        let localHash = installedPackageHashByProvider[provider.id]
        return localHash != remoteHash
    }

    private func actionStyle(for provider: TrafficProvider) -> ProviderCard.ActionStyle {
        if isUpdateAvailable(provider: provider) {
            return .update
        }
        if isInstalled(provider: provider) {
            return .reinstall
        }
        return .install
    }

    private func needsInitialization(provider: TrafficProvider) -> Bool {
        guard isInstalled(provider: provider) else { return false }
        return !(pendingRuleSetsByProvider[provider.id] ?? []).isEmpty
    }
    
}

private struct MarketSectionHeader: View {
    let onOpenMarket: () -> Void
    let onOpenImport: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("推荐供应商")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.54))

            Spacer(minLength: 12)

            HeaderActionButton(
                title: "供应商市场",
                systemImage: "shippingbox",
                kind: .secondary,
                action: onOpenMarket
            )

            HeaderActionButton(
                title: "导入安装",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                action: onOpenImport
            )
        }
    }
}

private struct HeaderActionButton: View {
    enum Kind {
        case primary
        case secondary
    }

    @Environment(\.colorScheme) private var scheme
    let title: String
    let systemImage: String
    let kind: Kind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: kind == .primary ? .bold : .semibold, design: .rounded))
                .foregroundStyle(kind == .primary ? .white : MeshFluxTheme.meshBlue)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, kind == .primary ? 14 : 12)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(kind == .primary ? AnyShapeStyle(MeshFluxTheme.meshBlue) : AnyShapeStyle(Color.white.opacity(scheme == .dark ? 0.08 : 0.26)))
                        .overlay {
                            if kind == .secondary {
                                Capsule(style: .continuous)
                                    .stroke(MeshFluxTheme.meshBlue.opacity(scheme == .dark ? 0.14 : 0.14), lineWidth: 1)
                            }
                        }
                }
                .shadow(color: kind == .primary ? MeshFluxTheme.meshBlue.opacity(0.16) : .clear, radius: 7, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct ProviderCard: View {
    enum ActionStyle {
        case install
        case reinstall
        case update

        var title: String {
            switch self {
            case .install: return "安装"
            case .reinstall: return "重新安装"
            case .update: return "更新"
            }
        }

        var tint: Color {
            switch self {
            case .install: return MeshFluxTheme.meshBlue
            case .reinstall: return MeshFluxTheme.meshCyan
            case .update: return MeshFluxTheme.meshAmber
            }
        }

        var usesFilledStyle: Bool {
            switch self {
            case .install:
                return true
            case .reinstall, .update:
                return false
            }
        }
    }

    @Environment(\.colorScheme) private var scheme
    let provider: TrafficProvider
    let isInstalling: Bool
    let actionStyle: ActionStyle
    let showInitBadge: Bool
    let onInstall: () -> Void

    private var visibleTags: [String] {
        Array(provider.tags.prefix(3))
    }

    private var hiddenTagCount: Int {
        max(provider.tags.count - visibleTags.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ProviderCardMeta(
                    name: provider.name,
                    author: provider.author,
                    showInitBadge: showInitBadge
                )

                Spacer()

                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 74, height: 34, alignment: .center)
                } else {
                    ProviderActionButton(actionStyle: actionStyle, action: onInstall)
                }
            }

            Text(provider.description)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.94))
                .lineLimit(2)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            ProviderCardTags(visibleTags: visibleTags, hiddenTagCount: hiddenTagCount)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(MeshFluxTheme.meshBlue.opacity(scheme == .dark ? 0.14 : 0.11), lineWidth: 1)
        )
        .shadow(color: MeshFluxTheme.meshBlue.opacity(scheme == .dark ? 0.08 : 0.03), radius: 8, x: 0, y: 3)
    }
}

private struct ProviderCardMeta: View {
    let name: String
    let author: String
    let showInitBadge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Text(author)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.9))

                if showInitBadge {
                    Text("待初始化")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(MeshFluxTheme.meshBlue.opacity(0.08))
                        .clipShape(Capsule(style: .continuous))
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                }
            }
        }
    }
}

private struct ProviderCardTags: View {
    @Environment(\.colorScheme) private var scheme
    let visibleTags: [String]
    let hiddenTagCount: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleTags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(scheme == .dark ? 0.08 : 0.30))
                    .clipShape(Capsule(style: .continuous))
                    .foregroundStyle(.secondary.opacity(0.88))
            }

            if hiddenTagCount > 0 {
                Text("+\(hiddenTagCount)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(scheme == .dark ? 0.08 : 0.24))
                    .clipShape(Capsule(style: .continuous))
                    .foregroundStyle(.secondary.opacity(0.82))
            }
        }
    }
}

private struct ProviderActionButton: View {
    @Environment(\.colorScheme) private var scheme
    let actionStyle: ProviderCard.ActionStyle
    let action: () -> Void

    var body: some View {
        Button(actionStyle.title) {
            action()
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5, weight: .bold, design: .rounded))
        .foregroundStyle(actionStyle.usesFilledStyle ? Color.white : buttonForeground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minWidth: 74, minHeight: 34)
        .background {
            Capsule(style: .continuous)
                .fill(buttonBackground)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(buttonStroke, lineWidth: actionStyle.usesFilledStyle ? 0 : 1)
                }
        }
    }

    private var buttonForeground: Color {
        switch actionStyle {
        case .install:
            return .white
        case .reinstall:
            return Color(red: 0.23, green: 0.62, blue: 0.70)
        case .update:
            return Color(red: 0.75, green: 0.54, blue: 0.08)
        }
    }

    private var buttonBackground: Color {
        switch actionStyle {
        case .install:
            return actionStyle.tint
        case .reinstall:
            return Color.white.opacity(scheme == .dark ? 0.08 : 0.26)
        case .update:
            return Color.white.opacity(scheme == .dark ? 0.08 : 0.24)
        }
    }

    private var buttonStroke: Color {
        switch actionStyle {
        case .install:
            return .clear
        case .reinstall:
            return Color(red: 0.23, green: 0.62, blue: 0.70).opacity(0.18)
        case .update:
            return Color(red: 0.75, green: 0.54, blue: 0.08).opacity(0.20)
        }
    }
}
