import SwiftUI
import VPNLibrary

struct MarketTabView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var vpnController: VPNController
    @State private var recommended: [TrafficProvider] = []
    @State private var installedPackageHashByProvider: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var cacheNotice: String?
    @State private var showMarketplace = false
    @State private var showInstalled = false
    @State private var showOfflineImport = false
    @State private var selectedRecommendedProvider: ProviderDetailContext?
    @State private var recommendedInstallProvider: TrafficProvider?
    @State private var uninstallTarget: RecommendedUninstallSelection?

    var body: some View {
        ZStack {
            MarketIOSTheme.windowBackground(scheme)
                .ignoresSafeArea()

            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        marketOverviewCard

                        HStack(spacing: 10) {
                            MarketTabActionButton(
                                title: "供应商市场",
                                subtitle: "浏览并安装推荐供应商",
                                systemImage: "shippingbox.fill",
                                tint: MarketIOSTheme.meshBlue,
                                prominent: true
                            ) {
                                showMarketplace = true
                            }
                            .frame(maxWidth: .infinity)

                            MarketTabActionButton(
                                title: "已安装",
                                subtitle: "管理本地 provider 资产",
                                systemImage: "tray.full.fill",
                                tint: MarketIOSTheme.meshCyan
                            ) {
                                showInstalled = true
                            }
                            .frame(maxWidth: .infinity)
                        }

                        MarketTabActionButton(
                            title: "导入安装",
                            subtitle: "通过 URL / JSON 本地导入",
                            systemImage: "square.and.arrow.down.fill",
                            tint: MarketIOSTheme.meshAmber
                        ) {
                            showOfflineImport = true
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear)

                Section("推荐供应商") {
                    if let cacheNotice, !cacheNotice.isEmpty {
                        Text(cacheNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(MarketIOSTheme.meshBlue)
                            Text("正在加载推荐列表…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let errorText, !errorText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Button("重试") {
                                Task { await loadRecommended() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(MarketIOSTheme.meshBlue)
                        }
                    } else if recommended.isEmpty {
                        Text("暂无推荐供应商")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recommended) { provider in
                            ProviderRecommendedRow(
                                provider: provider,
                                localHash: installedPackageHashByProvider[provider.id] ?? "",
                                onQuickAction: {
                                    recommendedInstallProvider = provider
                                },
                                onOpenDetail: {
                                    selectedRecommendedProvider = ProviderDetailContext(
                                        providerID: provider.id,
                                        displayName: provider.name,
                                        provider: provider,
                                        localHash: installedPackageHashByProvider[provider.id] ?? "",
                                        pendingTags: []
                                    )
                                }
                            )
                        }
                    }
                }
                .listRowBackground(MarketIOSTheme.cardFill(scheme))
            }
            .listStyle(.insetGrouped)
            .marketIOSListBackgroundHidden()
        }
        .navigationTitle("Market")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadRecommended() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(MarketIOSTheme.meshBlue)
                .disabled(isLoading)
            }
        }
        .sheet(isPresented: $showMarketplace) {
            NavigationView {
                ProviderMarketplaceView()
            }
        }
        .sheet(isPresented: $showInstalled) {
            NavigationView {
                InstalledProvidersView()
            }
        }
        .sheet(isPresented: $showOfflineImport) {
            NavigationView {
                OfflineImportViewIOS()
            }
        }
        .sheet(item: $selectedRecommendedProvider) { detail in
            NavigationView {
                ProviderDetailHubView(
                    context: detail,
                    onAction: { action in
                        switch action {
                        case .install, .update, .reinstall:
                            recommendedInstallProvider = detail.provider
                        case .uninstall:
                            uninstallTarget = RecommendedUninstallSelection(
                                providerID: detail.providerID,
                                providerName: detail.displayName
                            )
                        }
                    }
                )
            }
        }
        .sheet(item: $recommendedInstallProvider) { provider in
            ProviderInstallWizardView(provider: provider) {
                Task { await loadRecommended() }
            }
        }
        .sheet(item: $uninstallTarget) { item in
            ProviderUninstallWizardView(
                providerID: item.providerID,
                providerName: item.providerName,
                vpnConnected: vpnController.isConnected
            ) {
                Task { await loadRecommended() }
            }
        }
        .task {
            if recommended.isEmpty {
                await loadRecommended()
            }
        }
        .refreshable {
            await loadRecommended()
        }
    }

    private var marketOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MarketIOSTheme.meshBlue, MarketIOSTheme.meshIndigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "shippingbox.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("MARKET NEXUS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(MarketIOSTheme.meshCyan)
                    Text("供应商市场")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("发现、安装、管理 Web3 供应商配置")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                MarketIOSChip(title: "\(recommended.count) 推荐", tint: MarketIOSTheme.meshCyan)
                if isLoading {
                    MarketIOSChip(title: "同步中", tint: MarketIOSTheme.meshBlue)
                } else {
                    MarketIOSChip(title: "状态就绪", tint: MarketIOSTheme.meshMint)
                }
                MarketIOSChip(title: "支持离线导入", tint: MarketIOSTheme.meshAmber)
            }
        }
        .marketIOSCard(horizontal: 14, vertical: 12)
    }

    private func loadRecommended() async {
        let localHash = await SharedPreferences.installedProviderPackageHash.get()
        await MainActor.run {
            installedPackageHashByProvider = localHash
        }

        let cached = MarketService.shared.getCachedRecommendedProviders()
        if !cached.isEmpty {
            await MainActor.run {
                recommended = cached
            }
        }

        await MainActor.run {
            isLoading = true
            errorText = nil
            cacheNotice = nil
        }
        do {
            let list = try await MarketService.shared.fetchMarketRecommendedCached()
            let refreshedLocalHash = await SharedPreferences.installedProviderPackageHash.get()
            await MainActor.run {
                recommended = list
                installedPackageHashByProvider = refreshedLocalHash
                isLoading = false
                cacheNotice = nil
            }
        } catch {
            await MainActor.run {
                isLoading = false
                if recommended.isEmpty {
                    errorText = "加载推荐供应商失败：\(error.localizedDescription)"
                } else {
                    errorText = nil
                    cacheNotice = "网络请求失败，当前显示本地缓存数据。"
                }
            }
        }
    }
}

private struct MarketTabActionButton: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(prominent ? Color.white : tint)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(prominent ? Color.white.opacity(0.22) : tint.opacity(scheme == .dark ? 0.24 : 0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(prominent ? .white : .primary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(prominent ? Color.white.opacity(0.84) : .secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(prominent ? Color.white.opacity(0.82) : tint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(backgroundShape)
            .overlay(strokeShape)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if prominent {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MarketIOSTheme.cardFill(scheme))
        }
    }

    @ViewBuilder
    private var strokeShape: some View {
        if prominent {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(scheme == .dark ? 0.54 : 0.30), lineWidth: 1)
        }
    }
}

private struct ProviderRecommendedRow: View {
    let provider: TrafficProvider
    let localHash: String
    let onQuickAction: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if let price = provider.price_per_gb_usd {
                    Text(String(format: "%.2f USD/GB", price))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MarketIOSTheme.meshCyan)
                }
                quickActionButton
            }
            Text(provider.description)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                ForEach(provider.tags.prefix(4), id: \.self) { tag in
                    MarketIOSChip(title: tag)
                }
            }
            Text("点击卡片查看详情")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .marketIOSCard(horizontal: 12, vertical: 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetail()
        }
    }

    @ViewBuilder
    private var quickActionButton: some View {
        if quickActionDisabled {
            RecommendedQuickActionControl(
                title: "已安装",
                tint: MarketIOSTheme.meshMint,
                prominent: false,
                disabled: true
            ) {}
        } else {
            RecommendedQuickActionControl(
                title: quickActionTitle,
                tint: quickActionTint,
                prominent: true
            ) {
                onQuickAction()
            }
        }
    }

    private var isInstalled: Bool {
        !localHash.isEmpty
    }

    private var isUpdateAvailable: Bool {
        guard let remoteHash = provider.package_hash, !remoteHash.isEmpty else { return false }
        guard !localHash.isEmpty else { return false }
        return remoteHash != localHash
    }

    private var quickActionTitle: String {
        if isUpdateAvailable { return "更新" }
        if isInstalled { return "已安装" }
        return "安装"
    }

    private var quickActionTint: Color {
        if isUpdateAvailable { return MarketIOSTheme.meshAmber }
        return MarketIOSTheme.meshBlue
    }

    private var quickActionDisabled: Bool {
        isInstalled && !isUpdateAvailable
    }
}

private struct RecommendedUninstallSelection: Identifiable {
    var id: String { providerID }
    let providerID: String
    let providerName: String
}

private struct RecommendedQuickActionControl: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let tint: Color
    let prominent: Bool
    var disabled: Bool = false
    var height: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .padding(.horizontal, 12)
                .frame(minWidth: 62, minHeight: height)
                .background(backgroundShape)
                .overlay(strokeShape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if prominent {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.20 : 0.14))
        }
    }

    private var strokeShape: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .stroke(tint.opacity(prominent ? 0.18 : (scheme == .dark ? 0.48 : 0.30)), lineWidth: 1)
    }

    private var textColor: Color {
        prominent ? .white : tint
    }
}

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

    static func buttonTint(isPrimary: Bool, isDanger: Bool = false) -> Color {
        if isDanger { return meshRed }
        return isPrimary ? meshBlue : meshCyan
    }
}

struct MarketIOSChip: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var tint: Color = MarketIOSTheme.meshBlue

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(MarketIOSTheme.chipFill(tint, scheme: scheme))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(MarketIOSTheme.chipStroke(tint, scheme: scheme), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
            .foregroundStyle(.secondary)
    }
}

private struct MarketIOSCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let horizontal: CGFloat
    let vertical: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MarketIOSTheme.cardFill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MarketIOSTheme.cardStroke(scheme), lineWidth: 1)
            )
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

struct MarketTabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MarketTabView()
        }
    }
}
