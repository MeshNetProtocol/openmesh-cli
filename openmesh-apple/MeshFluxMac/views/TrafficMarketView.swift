import SwiftUI
import AppKit
import VPNLibrary

struct TrafficMarketView: View {
    @ObservedObject var vpnController: VPNController
    @State private var providers: [TrafficProvider] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var installingId: String?
    @State private var installedProviderIDs: Set<String> = []
    @State private var installedPackageHashByProvider: [String: String] = [:]
    @State private var pendingRuleSetsByProvider: [String: [String]] = [:]
    
    var body: some View {
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
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task { await loadData() }
                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
                .foregroundStyle(.primary)
            Spacer()
            Button {
                ProviderMarketWindowManager.shared.show(vpnController: vpnController)
            } label: {
                Label("供应商市场", systemImage: "shippingbox")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                OfflineImportWindowManager.shared.show(onInstalled: {
                    Task { await reloadInstalledState() }
                })
            } label: {
                Label("导入安装", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
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
    let provider: TrafficProvider
    let isInstalling: Bool
    let actionTitle: String
    let showUpdateBadge: Bool
    let showInitBadge: Bool
    let onInstall: () -> Void
    
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
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(6)
                                .foregroundStyle(.orange)
                        }
                        if showInitBadge {
                            Text("Init")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(6)
                                .foregroundStyle(.blue)
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
                    .tint(.blue)
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
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}
