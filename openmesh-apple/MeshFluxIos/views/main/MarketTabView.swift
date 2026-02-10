import SwiftUI

struct MarketTabView: View {
    @State private var recommended: [TrafficProvider] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showMarketplace = false
    @State private var showInstalled = false
    @State private var showOfflineImport = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            showMarketplace = true
                        } label: {
                            Label("供应商市场", systemImage: "shippingbox")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showInstalled = true
                        } label: {
                            Label("已安装", systemImage: "tray.full")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 10) {
                        Button {
                            showOfflineImport = true
                        } label: {
                            Label("导入安装", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Spacer(minLength: 0)
                    }

                    Text("在线供应商与本地已安装已拆分为独立页面。")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("推荐供应商") {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
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
                        .buttonStyle(.bordered)
                    }
                } else if recommended.isEmpty {
                    Text("暂无推荐供应商")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recommended) { provider in
                        ProviderRecommendedRow(provider: provider)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Market")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadRecommended() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
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
        .task {
            if recommended.isEmpty {
                await loadRecommended()
            }
        }
        .refreshable {
            await loadRecommended()
        }
    }

    private func loadRecommended() async {
        await MainActor.run {
            isLoading = true
            errorText = nil
        }
        do {
            let list = try await MarketService.shared.fetchMarketRecommendedCached()
            await MainActor.run {
                recommended = list
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorText = "加载推荐供应商失败：\(error.localizedDescription)"
                recommended = []
            }
        }
    }
}

private struct ProviderRecommendedRow: View {
    let provider: TrafficProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if let price = provider.price_per_gb_usd {
                    Text(String(format: "%.2f USD/GB", price))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Text(provider.description)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                ForEach(provider.tags.prefix(4), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MarketTabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MarketTabView()
        }
    }
}
