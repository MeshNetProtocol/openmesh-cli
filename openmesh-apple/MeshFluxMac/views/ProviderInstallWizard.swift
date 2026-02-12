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
    @Environment(\.colorScheme) private var scheme

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
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 12) {
                headerSection

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        introSection
                        metaSection
                        stepsSection

                        if let errorText {
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
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .topLeading)
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

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("安装供应商")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MeshFluxTheme.meshBlue, MeshFluxTheme.meshCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(provider.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
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

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("此安装向导会把供应商配置落盘到 App Group 并做基础自检。若该供应商声明了 rule-set，会尝试在安装阶段下载；若 URL 在当前网络不可达，将在首次连接后自动初始化（无需弹窗）。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("安装完成后切换到该供应商", isOn: $selectAfterInstall)
                .toggleStyle(.checkbox)
                .disabled(isRunning || finished)
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

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("元数据")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            metaRow(label: "provider_id", value: provider.id)
            metaRow(label: "provider_hash", value: provider.provider_hash ?? "-")
            metaRow(label: "package_hash", value: provider.package_hash ?? "-")
            metaRow(label: "local_installed_package_hash", value: localInstalledPackageHash.isEmpty ? "-" : localInstalledPackageHash)
            metaRow(label: "pending_rule_sets", value: pendingRuleSets.isEmpty ? "-" : pendingRuleSets.joined(separator: ", "))
            metaRow(label: "market_updated_at", value: marketUpdatedAt.isEmpty ? "-" : marketUpdatedAt)
            metaRow(label: "market_etag", value: marketETag.isEmpty ? "-" : marketETag)
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
        .textSelection(.enabled)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("安装步骤")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName(for: step.status))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor(for: step.status))
                        .frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        if let message = step.message, !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
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

    private func errorSection(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))

            Text(text)
                .font(.caption)
                .foregroundStyle(Color(red: 0.88, green: 0.30, blue: 0.36))
                .textSelection(.enabled)
            Spacer()
            Button("复制") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
            .buttonStyle(.bordered)
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
                Button("完成") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .tint(MeshFluxTheme.meshBlue)
            } else if isRunning {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(MeshFluxTheme.meshBlue)
                    Text(runningHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 360, alignment: .trailing)
                }
            } else {
                Button(errorText == nil ? "开始安装" : "重试") {
                    Task { await runInstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MeshFluxTheme.meshBlue)
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.caption.monospaced())
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

    private func iconName(for status: StepState.Status) -> String {
        switch status {
        case .pending:
            return "circle"
        case .running:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
    }

    private func iconColor(for status: StepState.Status) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .running:
            return MeshFluxTheme.meshBlue
        case .success:
            return MeshFluxTheme.meshMint
        case .failure:
            return Color(red: 0.88, green: 0.30, blue: 0.36)
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
