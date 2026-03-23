//
//  OpenMeshTopBarView.swift
//  MeshFluxMac
//
//  V2 OpenMesh 顶部"当前供应商"状态条。
//  设计参照 OpenRouter 顶部 model 选择器：主体是"当前在用谁"，而不是列表入口。
//  阶段 1：静态占位。阶段 3 接入 MeshWalletStore，阶段 4 接入当前激活供应商状态。
//

import SwiftUI

struct OpenMeshTopBarView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            // 当前激活供应商
            activeProviderCard
            // 账户余额行
            balanceRow
        }
    }

    // MARK: - 当前激活供应商卡片

    private var activeProviderCard: some View {
        HStack(spacing: 12) {
            // 供应商图标占位
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MeshFluxTheme.meshBlue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "network")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("未选择供应商")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    // 状态徽章
                    Text("未连接")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text("选择一个供应商开始使用")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // 切换按钮
            Button {
                // 阶段 4 接入：展开供应商列表或弹出选择器
            } label: {
                HStack(spacing: 4) {
                    Text("切换")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(MeshFluxTheme.meshBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(MeshFluxTheme.meshBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
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

    // MARK: - 余额行

    private var balanceRow: some View {
        HStack(spacing: 0) {
            // 余额
            HStack(spacing: 5) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(MeshFluxTheme.meshMint)
                Text("金豆账户")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("—")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)

            // 本次用量
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("本次 0 MB")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // 充值入口
            Button {
                // 阶段 3 接入：打开充值引导
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("充值")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(MeshFluxTheme.meshBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    ZStack {
        MeshFluxWindowBackground()
        OpenMeshTopBarView()
            .padding()
    }
    .frame(width: 420)
}
