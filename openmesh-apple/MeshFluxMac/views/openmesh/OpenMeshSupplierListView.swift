//
//  OpenMeshSupplierListView.swift
//  MeshFluxMac
//
//  V2 链上供应商浏览列表。
//  设计思路：类比 OpenRouter 的 model 列表——核心维度是价格(金豆/MB)、
//  服务类型、地区覆盖、节点数量。用户"切换供应商"而不是"安装 VPN 服务器"。
//  阶段 1：静态 mock 数据。阶段 4 替换为 OnChainSupplierViewModel。
//

import SwiftUI

// MARK: - 服务类型

enum SupplierServiceType: String {
    case general  = "通用"
    case ai       = "AI 专用"
    case commerce = "电商专用"

    var color: Color {
        switch self {
        case .general:  return MeshFluxTheme.meshBlue
        case .ai:       return MeshFluxTheme.meshCyan
        case .commerce: return MeshFluxTheme.meshAmber
        }
    }

    var icon: String {
        switch self {
        case .general:  return "globe"
        case .ai:       return "brain"
        case .commerce: return "cart"
        }
    }
}

// MARK: - 主视图

struct OpenMeshSupplierListView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selectedType: SupplierServiceType? = nil   // nil = 全部

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 筛选栏
            filterBar
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // 列表
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filteredSuppliers) { item in
                        SupplierRowView(item: item)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - 筛选栏

    private var filterBar: some View {
        HStack(spacing: 6) {
            filterChip(label: "全部", type: nil)
            filterChip(label: "通用", type: .general)
            filterChip(label: "AI 专用", type: .ai)
            filterChip(label: "电商专用", type: .commerce)
            Spacer(minLength: 0)
            Button {
                // 阶段 4：refresh
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func filterChip(label: String, type: SupplierServiceType?) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isSelected ? (type?.color ?? MeshFluxTheme.meshBlue) : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(isSelected
                            ? (type?.color ?? MeshFluxTheme.meshBlue).opacity(0.12)
                            : Color.secondary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据过滤

    private var filteredSuppliers: [SupplierMockItem] {
        guard let t = selectedType else { return SupplierMockData.samples }
        return SupplierMockData.samples.filter { $0.serviceType == t }
    }
}

// MARK: - 单行供应商卡片

struct SupplierRowView: View {
    @Environment(\.colorScheme) private var scheme
    let item: SupplierMockItem

    var body: some View {
        MeshFluxCard(cornerRadius: 12) {
            HStack(spacing: 12) {

                // 左：类型图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.serviceType.color.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: item.serviceType.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.serviceType.color)
                }

                // 中：名称 + 元数据
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        // 服务类型徽章
                        Text(item.serviceType.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(item.serviceType.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(item.serviceType.color.opacity(0.1), in: Capsule())
                    }
                    // 地区 + 节点数
                    HStack(spacing: 8) {
                        metaTag(icon: "location", text: item.regions)
                        metaTag(icon: "server.rack", text: "\(item.serverCount) 节点")
                    }
                }

                Spacer(minLength: 0)

                // 右：价格 + 切换按钮
                VStack(alignment: .trailing, spacing: 6) {
                    // 价格（核心维度，类比 token 价格）
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.priceDisplay)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(MeshFluxTheme.meshMint)
                        Text("金豆 / MB")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        // 阶段 6 接入：x402 支付 + 自动配置安装
                    } label: {
                        Text("切换")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(MeshFluxTheme.meshBlue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func metaTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mock 数据（阶段 4 替换）

struct SupplierMockItem: Identifiable {
    let id: String
    let name: String
    let serviceType: SupplierServiceType
    let priceDisplay: String     // 例："0.08"
    let regions: String          // 例："亚太 · 欧美"
    let serverCount: Int
}

enum SupplierMockData {
    static let samples: [SupplierMockItem] = [
        SupplierMockItem(
            id: "s-001",
            name: "FastNode Global",
            serviceType: .general,
            priceDisplay: "0.05",
            regions: "亚太 · 欧美 · 中东",
            serverCount: 120
        ),
        SupplierMockItem(
            id: "s-002",
            name: "AIRoute Pro",
            serviceType: .ai,
            priceDisplay: "0.03",
            regions: "北美 · 欧洲",
            serverCount: 48
        ),
        SupplierMockItem(
            id: "s-003",
            name: "ShopSpeed",
            serviceType: .commerce,
            priceDisplay: "0.04",
            regions: "亚太",
            serverCount: 30
        ),
        SupplierMockItem(
            id: "s-004",
            name: "SecureLink",
            serviceType: .general,
            priceDisplay: "0.08",
            regions: "全球 50+ 地区",
            serverCount: 200
        ),
    ]
}

#Preview {
    ZStack {
        MeshFluxWindowBackground()
        OpenMeshSupplierListView()
    }
    .frame(width: 420, height: 500)
}
