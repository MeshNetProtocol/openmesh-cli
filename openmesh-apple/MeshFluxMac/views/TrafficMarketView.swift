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
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(MeshFluxTheme.meshBlue)
                        Text("Loading market...")
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
                        Button("Retry") {
                            Task { await loadData() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MeshFluxTheme.meshBlue)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if installedProviderIDs.isEmpty {
                                Text("尚未选择供应商：可先导入安装，或打开供应商市场选择在线供应商。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            }
                            if providers.isEmpty {
                                Text("暂无推荐供应商，可点击右上角“供应商市场”查看全部供应商。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            }
                            ForEach(providers) { provider in
                                ProviderCard(
                                    provider: provider,
                                    isInstalling: installingId == provider.id,
                                    actionTitle: actionTitle(for: provider),
                                    showUpdateBadge: isUpdateAvailable(provider: provider)
                                    ,
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
        HStack {
            Text("推荐供应商")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [MeshFluxTheme.meshBlue, MeshFluxTheme.meshCyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Spacer()
            Button {
                ProviderMarketWindowManager.shared.show(vpnController: vpnController)
            } label: {
                Label("供应商市场", systemImage: "shippingbox")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(MeshFluxTheme.meshBlue)
            Button {
                OfflineImportWindowManager.shared.show(onInstalled: {
                    Task { await reloadInstalledState() }
                })
            } label: {
                Label("导入安装", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(MeshFluxTheme.meshBlue)
        }
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

    private func actionTitle(for provider: TrafficProvider) -> String {
        if isUpdateAvailable(provider: provider) { return "Update" }
        if isInstalled(provider: provider) { return "Reinstall" }
        return "Install"
    }

    private func needsInitialization(provider: TrafficProvider) -> Bool {
        guard isInstalled(provider: provider) else { return false }
        return !(pendingRuleSetsByProvider[provider.id] ?? []).isEmpty
    }
    
}

struct ProviderCard: View {
    @Environment(\.colorScheme) private var scheme
    let provider: TrafficProvider
    let isInstalling: Bool
    let actionTitle: String
    let showUpdateBadge: Bool
    let showInitBadge: Bool
    let onInstall: () -> Void

    private var actionTint: Color {
        if actionTitle == "Update" { return MeshFluxTheme.meshAmber }
        if actionTitle == "Reinstall" { return MeshFluxTheme.meshCyan }
        return MeshFluxTheme.meshBlue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                        if showUpdateBadge {
                            Text("Update")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MeshFluxTheme.meshAmber.opacity(0.16))
                                .cornerRadius(6)
                                .foregroundStyle(MeshFluxTheme.meshAmber)
                        }
                        if showInitBadge {
                            Text("Init")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MeshFluxTheme.meshBlue.opacity(0.14))
                                .cornerRadius(6)
                                .foregroundStyle(MeshFluxTheme.meshBlue)
                        }
                    }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(provider.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 60)
                } else {
                    Button(actionTitle) {
                        onInstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(actionTint)
                }
            }
            
            Text(provider.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 6) {
                ForEach(provider.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MeshFluxTheme.meshBlue.opacity(0.12))
                        .cornerRadius(4)
                        .foregroundStyle(.secondary.opacity(0.95))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
        .shadow(color: MeshFluxTheme.meshBlue.opacity(scheme == .dark ? 0.12 : 0.06), radius: 8, x: 0, y: 3)
    }
}
