import AppKit
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
    let installAction: (@Sendable (@escaping @Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)?
    let onInstallingChange: (Bool) -> Void
    let onClose: () -> Void

    @State private var steps: [StepState] = []
    @State private var isRunning = false
    @State private var selectAfterInstall = true
    @State private var errorText: String?
    @State private var finished = false
    @State private var currentRunningStep: MarketService.InstallStep?
    @State private var marketUpdatedAt: String = ""
    @State private var marketETag: String = ""
    @State private var localInstalledPackageHash: String = ""
    @State private var pendingRuleSets: [String] = []

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

            Text("此安装向导会把供应商配置落盘到 App Group 并做基础自检。若该供应商声明了 rule-set，会尝试在安装阶段下载；若 URL 在当前网络不可达，将在首次连接后自动初始化（无需弹窗）。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("安装完成后切换到该供应商", isOn: $selectAfterInstall)
                .disabled(isRunning || finished)

            VStack(alignment: .leading, spacing: 4) {
                Text("provider_id：\(provider.id)")
                Text("provider_hash：\(provider.provider_hash ?? "-")")
                Text("package_hash：\(provider.package_hash ?? "-")")
                Text("local_installed_package_hash：\(localInstalledPackageHash.isEmpty ? "-" : localInstalledPackageHash)")
                Text("pending_rule_sets：\(pendingRuleSets.isEmpty ? "-" : pendingRuleSets.joined(separator: ", "))")
                Text("market_updated_at：\(marketUpdatedAt.isEmpty ? "-" : marketUpdatedAt)")
                Text("market_etag：\(marketETag.isEmpty ? "-" : marketETag)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

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
                HStack(alignment: .top, spacing: 10) {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                    Button("复制") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(errorText, forType: .string)
                    }
                }
            }

            HStack {
                Button("取消") { onClose() }
                    .disabled(isRunning)
                Spacer()
                if finished {
                    Button("完成") { onClose() }
                } else if isRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(runningHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 320, alignment: .trailing)
                    }
                } else {
                    Button(errorText == nil ? "开始安装" : "重试") {
                        Task { await runInstall() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 620, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if steps.isEmpty {
                steps = defaultSteps()
            }
            Task {
                marketUpdatedAt = await SharedPreferences.marketManifestUpdatedAt.get()
                marketETag = await SharedPreferences.marketManifestETag.get()
                let map = await SharedPreferences.installedProviderPackageHash.get()
                localInstalledPackageHash = map[provider.id] ?? ""
                let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
                pendingRuleSets = pending[provider.id] ?? []
            }
        }
    }

    private func defaultSteps() -> [StepState] {
        [
            .init(id: .fetchDetail, title: "读取供应商详情", status: .pending, message: nil),
            .init(id: .downloadConfig, title: "下载配置文件", status: .pending, message: nil),
            .init(id: .validateConfig, title: "解析配置文件", status: .pending, message: nil),
            .init(id: .downloadRoutingRules, title: "下载 routing_rules.json（可选）", status: .pending, message: nil),
            .init(id: .writeRoutingRules, title: "写入 routing_rules.json（可选）", status: .pending, message: nil),
            .init(id: .downloadRuleSet, title: "下载 rule-set（可选）", status: .pending, message: nil),
            .init(id: .writeRuleSet, title: "写入 rule-set（可选）", status: .pending, message: nil),
            .init(id: .writeConfig, title: "写入 config.json", status: .pending, message: nil),
            .init(id: .registerProfile, title: "注册到供应商列表", status: .pending, message: nil),
            .init(id: .finalize, title: "完成", status: .pending, message: nil),
        ]
    }

    private func runInstall() async {
        errorText = nil
        finished = false
        isRunning = true
        currentRunningStep = nil
        onInstallingChange(true)
        for i in steps.indices {
            steps[i].status = .pending
            steps[i].message = nil
        }

        func update(step: MarketService.InstallStep, message: String) {
            if currentRunningStep != step {
                if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                    steps[runningIndex].status = .success
                }
                currentRunningStep = step
            }
            if let idx = steps.firstIndex(where: { $0.id == step }) {
                steps[idx].status = .running
                steps[idx].message = message
            }
        }

        do {
            await MainActor.run {
                update(step: .fetchDetail, message: "开始安装")
            }
            let progressHandler: @Sendable (MarketService.InstallProgress) -> Void = { p in
                Task { @MainActor in
                    update(step: p.step, message: p.message)
                }
            }
            try await Task.detached(priority: .userInitiated) {
                if let installAction {
                    try await installAction(progressHandler)
                } else {
                    try await MarketService.shared.installProvider(
                        provider: provider,
                        selectAfterInstall: selectAfterInstall,
                        progress: progressHandler
                    )
                }
            }.value
            await MainActor.run {
                if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                    steps[runningIndex].status = .success
                }
                if let finalizeIndex = steps.firstIndex(where: { $0.id == .finalize }) {
                    steps[finalizeIndex].status = .success
                }
                finished = true
                currentRunningStep = nil
            }
            let map = await SharedPreferences.installedProviderPackageHash.get()
            let pending = await SharedPreferences.installedProviderPendingRuleSetTags.get()
            await MainActor.run {
                localInstalledPackageHash = map[provider.id] ?? ""
                pendingRuleSets = pending[provider.id] ?? []
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
                currentRunningStep = nil
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

    private var runningHint: String {
        if let running = steps.first(where: { $0.status == .running }) {
            if let msg = running.message, !msg.isEmpty {
                return msg
            }
            return "正在执行：\(running.title)…"
        }
        return "正在运行…"
    }
}
