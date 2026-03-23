//
//  OpenMeshDIYView.swift
//  MeshFluxMac
//
//  V2 DIY 自建引导页。
//  设计要点：
//  - 不依赖钱包状态、余额、链上可用性
//  - 即使供应商列表失败，DIY 路径始终可用
//  - 提供两个行动路径：打开官方自建教程 / 直接导入本地配置
//  阶段 5 会接入真实的外部链接和 OfflineImportWindowManager。
//

import SwiftUI
import AppKit

struct OpenMeshDIYView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // 说明区块
                descriptionCard

                // 行动按钮区块
                actionsCard

                // 商业 vs DIY 对比说明
                comparisonCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - 说明区块

    private var descriptionCard: some View {
        MeshFluxCard(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(MeshFluxTheme.meshCyan)
                    Text("自建节点模式")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text("如果你有自己的服务器，或者在团队内部部署节点，可以通过以下方式接入 MeshFlux，无需购买商业服务。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 行动按钮

    private var actionsCard: some View {
        VStack(spacing: 10) {
            // 主按钮：打开自建教程
            Button {
                // 阶段 5 接入：NSWorkspace.shared.open(vendorConsoleTutorialURL)
                // 占位：打印日志
                NSLog("OpenMeshDIYView: open vendor-console tutorial (placeholder)")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("打开自建教程")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("查看如何在自己的服务器上部署节点")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MeshFluxTheme.cardFill(scheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)

            // 次按钮：导入本地配置
            Button {
                // 阶段 5 接入：OfflineImportWindowManager.shared.show()
                NSLog("OpenMeshDIYView: open offline import (placeholder)")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(MeshFluxTheme.meshMint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("直接导入本地配置")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("从本地文件导入已有的配置，跳过在线服务")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MeshFluxTheme.cardFill(scheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 对比说明

    private var comparisonCard: some View {
        MeshFluxCard(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("商业服务 vs 自建节点")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    comparisonRow(
                        icon: "sparkles",
                        iconColor: MeshFluxTheme.meshBlue,
                        title: "商业供应商",
                        detail: "一键使用，按月付费，适合普通用户"
                    )
                    Divider().opacity(0.4)
                    comparisonRow(
                        icon: "wrench.and.screwdriver",
                        iconColor: MeshFluxTheme.meshCyan,
                        title: "DIY 自建",
                        detail: "完全掌控，适合开发者和团队内部部署"
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func comparisonRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ZStack {
        MeshFluxWindowBackground()
        OpenMeshDIYView()
    }
    .frame(width: 520, height: 500)
}
