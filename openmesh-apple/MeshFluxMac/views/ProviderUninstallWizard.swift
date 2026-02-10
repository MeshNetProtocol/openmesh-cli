import SwiftUI

struct ProviderUninstallWizard: View {
    @ObservedObject var vpnController: VPNController
    let providerID: String
    let providerName: String
    let onFinished: () -> Void
    let onClose: () -> Void

    @State private var steps: [StepState] = []
    @State private var isRunning = false
    @State private var errorText: String?
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("卸载供应商")
                        .font(.headline)
                    Text(providerName.isEmpty ? providerID : providerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(providerID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("关闭") { onClose() }
                    .disabled(isRunning)
            }

            VStack(alignment: .leading, spacing: 10) {
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
                            }
                        }
                        Spacer(minLength: 0)
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

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if finished {
                    Button("完成") {
                        onFinished()
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("开始卸载") {
                        Task { await runUninstall() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                }
            }
        }
        .padding(14)
        .onAppear {
            if steps.isEmpty {
                steps = StepState.defaultSteps()
            }
        }
        .frame(minWidth: 640, minHeight: 520)
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
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
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
