import SwiftUI
import VPNLibrary

struct ProviderInstallWizard: View {
    struct StepState: Identifiable {
        enum Status {
            case pending
            case running
            case success
            case failure
        }

        let id: MarketService.InstallStep
        var title: String
        var status: Status
        var message: String?
    }

    let provider: TrafficProvider
    let onInstallingChange: (Bool) -> Void
    let onClose: () -> Void

    @State private var steps: [StepState] = []
    @State private var isRunning = false
    @State private var selectAfterInstall = true
    @State private var errorText: String?
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("安装供应商")
                        .font(.headline)
                    Text(provider.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { onClose() }
                    .disabled(isRunning)
            }

            Text("此安装向导会把供应商配置落盘到 App Group 并做基础自检。rule-set 的下载将在连接时由 sing-box 处理；若下载失败，会影响连接稳定性（TODO：后续在此处提供可选镜像/导入能力）。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("安装完成后切换到该供应商", isOn: $selectAfterInstall)
                .disabled(isRunning || finished)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Text(symbol(for: step.status))
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.system(size: 13, weight: .semibold))
                            if let message = step.message, !message.isEmpty {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") { onClose() }
                    .disabled(isRunning)
                Spacer()
                if finished {
                    Button("完成") { onClose() }
                } else if isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(errorText == nil ? "开始安装" : "重试") {
                        Task { await runInstall() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(width: 620)
        .onAppear {
            if steps.isEmpty {
                steps = defaultSteps()
            }
        }
    }

    private func defaultSteps() -> [StepState] {
        [
            .init(id: .fetchDetail, title: "读取供应商详情", status: .pending, message: nil),
            .init(id: .downloadConfig, title: "下载配置文件", status: .pending, message: nil),
            .init(id: .validateConfig, title: "解析配置文件", status: .pending, message: nil),
            .init(id: .writeConfig, title: "写入 config.json", status: .pending, message: nil),
            .init(id: .downloadRoutingRules, title: "下载 routing_rules.json（可选）", status: .pending, message: nil),
            .init(id: .writeRoutingRules, title: "写入 routing_rules.json（可选）", status: .pending, message: nil),
            .init(id: .noteRuleSetDownload, title: "rule-set 下载策略（TODO）", status: .pending, message: nil),
            .init(id: .registerProfile, title: "注册到供应商列表", status: .pending, message: nil),
            .init(id: .finalize, title: "完成", status: .pending, message: nil),
        ]
    }

    private func runInstall() async {
        errorText = nil
        finished = false
        isRunning = true
        onInstallingChange(true)
        for i in steps.indices {
            steps[i].status = .pending
            steps[i].message = nil
        }

        func update(step: MarketService.InstallStep, message: String) {
            if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                steps[runningIndex].status = .success
            }
            if let idx = steps.firstIndex(where: { $0.id == step }) {
                steps[idx].status = .running
                steps[idx].message = message
            }
        }

        do {
            try await MarketService.shared.installProvider(
                provider: provider,
                selectAfterInstall: selectAfterInstall,
                progress: { p in
                    Task { @MainActor in
                        update(step: p.step, message: p.message)
                    }
                }
            )
            await MainActor.run {
                if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                    steps[runningIndex].status = .success
                }
                if let finalizeIndex = steps.firstIndex(where: { $0.id == .finalize }) {
                    steps[finalizeIndex].status = .success
                }
                finished = true
            }
        } catch {
            await MainActor.run {
                if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                    steps[runningIndex].status = .failure
                    steps[runningIndex].message = error.localizedDescription
                } else if let firstPending = steps.firstIndex(where: { $0.status == .pending }) {
                    steps[firstPending].status = .failure
                    steps[firstPending].message = error.localizedDescription
                }
                errorText = "安装失败：\(error.localizedDescription)"
            }
        }

        await MainActor.run {
            isRunning = false
            onInstallingChange(false)
        }
    }

    private func symbol(for status: StepState.Status) -> String {
        switch status {
        case .pending:
            return "○"
        case .running:
            return "◐"
        case .success:
            return "●"
        case .failure:
            return "×"
        }
    }
}
