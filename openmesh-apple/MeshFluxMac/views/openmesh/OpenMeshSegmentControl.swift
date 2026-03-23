//
//  OpenMeshSegmentControl.swift
//  MeshFluxMac
//
//  V2 OpenMesh 分段切换控件：链上供应商 / DIY 自建。
//  阶段 1：纯 UI，无外部依赖。
//

import SwiftUI

enum OpenMeshSegment: String, CaseIterable {
    case suppliers = "链上供应商"
    case diy       = "DIY 自建"
}

struct OpenMeshSegmentControl: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selected: OpenMeshSegment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OpenMeshSegment.allCases, id: \.self) { seg in
                segButton(seg)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(scheme == .dark
                    ? Color.white.opacity(0.07)
                    : Color.black.opacity(0.06))
        }
    }

    private func segButton(_ seg: OpenMeshSegment) -> some View {
        let isSelected = selected == seg
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selected = seg }
        } label: {
            Text(seg.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected
                    ? (scheme == .dark ? Color.white : Color.black).opacity(0.92)
                    : Color.secondary.opacity(0.75))
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(scheme == .dark
                                ? Color.white.opacity(0.13)
                                : Color.white.opacity(0.90))
                            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

private struct SegmentPreviewWrapper: View {
    @State private var seg = OpenMeshSegment.suppliers
    var body: some View {
        OpenMeshSegmentControl(selected: $seg)
            .padding()
            .frame(width: 320)
    }
}

#Preview {
    SegmentPreviewWrapper()
}
