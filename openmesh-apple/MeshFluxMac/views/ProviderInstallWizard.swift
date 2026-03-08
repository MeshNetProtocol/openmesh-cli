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
    let installAction: (@Sendable (Bool, @escaping @Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)?
    let initialSelectAfterInstall: Bool
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
    @State private var showMetaDetails = false

    var body: some View {
        ZStack {
            MeshFluxWindowBackground()

            VStack(alignment: .leading, spacing: 12) {
                headerSection

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        introSection
                        stepsSection
                        metaSection

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
                selectAfterInstall = initialSelectAfterInstall
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
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("安装供应商")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(MeshFluxTheme.meshBlue.opacity(0.72))

                Text(provider.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("导入供应商配置并执行基础校验。安装完成后可立即切换到该供应商。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    installBadge(title: "官方来源", tint: MeshFluxTheme.meshBlue)
                    installBadge(title: pendingRuleSets.isEmpty ? "可直接安装" : "含可选资源", tint: pendingRuleSets.isEmpty ? MeshFluxTheme.meshMint : MeshFluxTheme.meshAmber)
                }
            }

            Spacer(minLength: 12)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.34, green: 0.39, blue: 0.45))
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.66))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MeshFluxTheme.meshBlue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("安装说明")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("安装会将供应商配置写入 App Group 并执行基础校验。如果供应商声明了 rule-set，会优先尝试下载；若当前网络不可达，将在首次连接后自动初始化。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle("安装完成后自动切换到该供应商", isOn: $selectAfterInstall)
                .toggleStyle(.checkbox)
                .disabled(isRunning || finished)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showMetaDetails.toggle()
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("技术详情")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("查看 provider id、hash 和市场元数据")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: showMetaDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MeshFluxTheme.meshBlue)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                compactMetaCard(label: "provider_id", value: provider.id)
                compactMetaCard(label: "package_hash", value: provider.package_hash ?? "-")
                compactMetaCard(label: "updated_at", value: marketUpdatedAt.isEmpty ? "-" : marketUpdatedAt)
            }

            if showMetaDetails {
                VStack(alignment: .leading, spacing: 8) {
                    metaRow(label: "provider_id", value: provider.id)
                    metaRow(label: "provider_hash", value: provider.provider_hash ?? "-")
                    metaRow(label: "package_hash", value: provider.package_hash ?? "-")
                    metaRow(label: "local_installed_package_hash", value: localInstalledPackageHash.isEmpty ? "-" : localInstalledPackageHash)
                    metaRow(label: "pending_rule_sets", value: pendingRuleSets.isEmpty ? "-" : pendingRuleSets.joined(separator: ", "))
                    metaRow(label: "market_updated_at", value: marketUpdatedAt.isEmpty ? "-" : marketUpdatedAt)
                    metaRow(label: "market_etag", value: marketETag.isEmpty ? "-" : marketETag)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MeshFluxTheme.cardStroke(scheme), lineWidth: 1)
        )
        .textSelection(.enabled)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("安装步骤")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(finished ? "安装已完成" : (isRunning ? runningHint : "确认后将按顺序执行下列步骤"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(MeshFluxTheme.meshBlue)
                } else if finished {
                    installBadge(title: "已完成", tint: MeshFluxTheme.meshMint)
                }
            }

            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(iconColor(for: step.status).opacity(step.status == .pending ? 0.10 : 0.16))
                            .frame(width: 24, height: 24)
                        Image(systemName: iconName(for: step.status))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(iconColor(for: step.status))
                    }
                    .frame(width: 28, alignment: .leading)
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
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(stepRowBackground(step.status))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MeshFluxTheme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                VStack(alignment: .trailing, spacing: 6) {
                    Text(selectAfterInstall ? "安装后将自动切换到当前供应商" : "安装后保持当前选择不变")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button(errorText == nil ? "开始安装" : "重试") {
                        Task { await runInstall() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MeshFluxTheme.meshBlue)
                }
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
            Text(value)
                .lineLimit(3)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.caption.monospaced())
    }

    private func compactMetaCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                }
        }
    }

    private func installBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            }
    }

    private func stepRowBackground(_ status: StepState.Status) -> Color {
        switch status {
        case .pending:
            return Color.white.opacity(0.08)
        case .running:
            return MeshFluxTheme.meshBlue.opacity(0.10)
        case .success:
            return MeshFluxTheme.meshMint.opacity(0.10)
        case .failure:
            return Color(red: 0.88, green: 0.30, blue: 0.36).opacity(0.10)
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
                    try await installAction(selectAfterInstall, progressHandler)
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
