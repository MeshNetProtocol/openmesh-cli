import SwiftUI

struct ProviderUninstallWizard: View {
    @ObservedObject var vpnController: VPNController
    let providerID: String
    let providerName: String
    let onFinished: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    @State private var steps: [StepState] = []
    @State private var isRunning = false
    @State private var errorText: String?
    @State private var finished = false

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 12) {
                headerSection

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        infoSection
                        stepsSection
                        if let errorText, !errorText.isEmpty {
                            errorSection(errorText)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider().overlay(MeshFluxTheme.meshBlue.opacity(0.16))
                actionSection
            }
            .padding(16)
        }
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .onAppear {
            if steps.isEmpty {
                steps = StepState.defaultSteps()
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("卸载供应商")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MeshFluxTheme.meshBlue, MeshFluxTheme.meshCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(providerName.isEmpty ? providerID : providerName)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(providerID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("关闭") { onClose() }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshAmber)
                .disabled(isRunning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("将从本地移除该供应商对应 profile、映射与缓存文件。若当前 VPN 正在使用该 profile，请先断开连接再卸载。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("卸载步骤")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(steps) { s in
                HStack(alignment: .top, spacing: 10) {
                    statusIcon(s.status)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title)
                            .font(.subheadline.weight(.semibold))
                        if !s.message.isEmpty {
                            Text(s.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private func errorSection(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))
            Text(text)
                .font(.caption)
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.88, green: 0.30, blue: 0.36).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.88, green: 0.30, blue: 0.36).opacity(0.32), lineWidth: 1)
        )
    }

    private var actionSection: some View {
        HStack {
            Button("取消") { onClose() }
                .buttonStyle(.bordered)
                .disabled(isRunning)

            Spacer()
            if finished {
                Button("完成") {
                    onFinished()
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshBlue)
            } else if isRunning {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(MeshFluxTheme.meshBlue)
                    Text(runningTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                }
            } else {
                Button("开始卸载") {
                    Task { await runUninstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshBlue)
                .disabled(isRunning)
            }
        }
    }

    private func runUninstall() async {
        errorText = nil
        finished = false
        isRunning = true
        steps = StepState.defaultSteps()

        func update(_ id: ProviderUninstallStep, status: StepStatus, message: String) {
            if let idx = steps.firstIndex(where: { $0.id == id }) {
                steps[idx].status = status
                steps[idx].message = message
            }
        }

        do {
            await MainActor.run {
                update(.validate, status: .running, message: "检查当前连接状态")
            }
            try await ProviderUninstaller.uninstall(
                providerID: providerID,
                vpnConnected: vpnController.isConnected,
                progress: { step, message in
                    Task { @MainActor in
                        for i in steps.indices {
                            if steps[i].status == .running, steps[i].id != step {
                                steps[i].status = .success
                            }
                        }
                        if let idx = steps.firstIndex(where: { $0.id == step }) {
                            steps[idx].status = step == .finalize ? .success : .running
                            steps[idx].message = message
                        }
                    }
                }
            )
            await MainActor.run {
                for i in steps.indices {
                    if steps[i].status == .running || steps[i].status == .pending {
                        steps[i].status = .success
                    }
                }
                finished = true
                isRunning = false
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
            }
        } catch {
            await MainActor.run {
                update(.finalize, status: .failed, message: "失败")
                errorText = error.localizedDescription
                isRunning = false
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView().scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MeshFluxTheme.meshMint)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))
        }
    }

    private var runningTitle: String {
        steps.first(where: { $0.status == .running })?.title ?? "正在卸载…"
    }
}

private enum StepStatus {
    case pending
    case running
    case success
    case failed
}

private struct StepState: Identifiable {
    var id: ProviderUninstallStep
    var title: String
    var message: String
    var status: StepStatus

    static func defaultSteps() -> [StepState] {
        [
            StepState(id: .validate, title: "校验状态", message: "", status: .pending),
            StepState(id: .removeProfile, title: "删除 Profile", message: "", status: .pending),
            StepState(id: .removePreferences, title: "清理映射", message: "", status: .pending),
            StepState(id: .removeFiles, title: "删除缓存文件", message: "", status: .pending),
            StepState(id: .finalize, title: "完成", message: "", status: .pending),
        ]
    }
}
