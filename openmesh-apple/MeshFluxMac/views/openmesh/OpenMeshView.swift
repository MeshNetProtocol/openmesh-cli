//
//  OpenMeshView.swift
//  MeshFluxMac
//
//  V2 OpenMesh 主界面。
//  设计参照 OpenRouter：顶部是"当前在用的供应商"，下方是可切换的供应商列表。
//  商用供应商切换时自动走安装流程；DIY 是自定义端点入口。
//  阶段 1：静态骨架。后续阶段逐步接入真实数据。
//

import SwiftUI

struct OpenMeshView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selectedSegment: OpenMeshSegment = .suppliers

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 0) {

                // ── 顶部：当前供应商 + 余额 ──────────────────────────────
                OpenMeshTopBarView()
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                // ── 分段切换 ─────────────────────────────────────────────
                OpenMeshSegmentControl(selected: $selectedSegment)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                // ── 内容区 ───────────────────────────────────────────────
                Group {
                    switch selectedSegment {
                    case .suppliers:
                        OpenMeshSupplierListView()
                    case .diy:
                        OpenMeshDIYView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

#Preview {
    OpenMeshView()
        .frame(width: 420, height: 680)
}
