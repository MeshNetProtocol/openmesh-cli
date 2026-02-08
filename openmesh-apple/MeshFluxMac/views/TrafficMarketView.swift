import SwiftUI
import VPNLibrary

struct TrafficMarketView: View {
    @State private var providers: [TrafficProvider] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var installingId: String? // ID of provider currently being installed
    
    var body: some View {
        VStack(spacing: 0) {
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
                        ForEach(providers) { provider in
                            ProviderCard(provider: provider, isInstalling: installingId == provider.id) {
                                Task {
                                    await install(provider)
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
    }
    
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            providers = try await MarketService.shared.fetchProviders()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func install(_ provider: TrafficProvider) async {
        installingId = provider.id
        do {
            try await MarketService.shared.downloadAndInstallProfile(provider: provider)
            // Success feedback? Maybe switch tab or show checkmark
            // Since we switch profile, the UI might update elsewhere.
            // Let's reset installing state.
        } catch {
            // Show alert? For now just print and maybe set error message
            print("Install failed: \(error)")
            // We might want to show a toast or alert here.
            // But since this is a simple implementation, let's just log it.
        }
        installingId = nil
    }
}

struct ProviderCard: View {
    let provider: TrafficProvider
    let isInstalling: Bool
    let onInstall: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
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
                    Button("Use") {
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
