//
//  EditProfileView.swift
//  MeshFluxMac
//
//  Edit profile name and config content (JSON). Aligned with sing-box EditProfileView + EditProfileContentView.
//

import SwiftUI
import VPNLibrary
import Network

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    var onSaved: (() -> Void)?

    @State private var profileName: String = ""
    @State private var configContent: String = ""
    @State private var isContentLoaded = false
    @State private var isSaving = false
    @State private var isContentChanged = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showContentEditor = false
    @State private var showServersEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("编辑配置")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField("配置名称", text: $profileName, prompt: Text("必填"))
                .textFieldStyle(.roundedBorder)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("配置内容 (JSON)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("编辑服务器") {
                            openServersEditor()
                        }
                        .buttonStyle(.bordered)
                        Button("编辑配置内容") {
                            loadContentIfNeeded()
                            showContentEditor = true
                        }
                        .buttonStyle(.bordered)
                    }
                    if isContentLoaded {
                        Text(configContent)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(6)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    } else {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity)
                            .padding(8)
                    }
                }
                .padding(8)
            }
            .groupBoxStyle(.automatic)

            HStack {
                Button("保存") {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 280)
        .onAppear {
            profileName = profile.name
            loadContentIfNeeded()
        }
        .sheet(isPresented: $showContentEditor) {
            ConfigContentEditorView(
                content: $configContent,
                isChanged: $isContentChanged,
                onSave: { saveContentOnly() }
            )
        }
        .sheet(isPresented: $showServersEditor) {
            ProfileServersEditorView(profile: profile) {
                Task { await reloadContent() }
                onSaved?()
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func loadContentIfNeeded() {
        guard !isContentLoaded else { return }
        Task {
            do {
                let content = try profile.read()
                await MainActor.run {
                    configContent = content
                    isContentLoaded = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "读取配置失败：\(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func reloadContent() async {
        do {
            let content = try profile.read()
            await MainActor.run {
                configContent = content
                isContentLoaded = true
                isContentChanged = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "读取配置失败：\(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func openServersEditor() {
        loadContentIfNeeded()
        if isContentChanged {
            errorMessage = "当前 JSON 有未保存的更改，请先保存/取消后再编辑服务器。"
            showError = true
            return
        }
        showServersEditor = true
    }

    /// Validates config content as JSON; returns nil if valid, otherwise error description.
    private func validateConfigJSON(_ content: String) -> String? {
        guard let data = content.data(using: .utf8) else { return "编码错误" }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return nil
        } catch {
            return "配置不是合法 JSON：\(error.localizedDescription)"
        }
    }

    private func saveProfile() {
        guard !profileName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if isContentChanged, isContentLoaded, let err = validateConfigJSON(configContent) {
            errorMessage = err
            showError = true
            return
        }
        isSaving = true
        Task {
            do {
                profile.name = profileName.trimmingCharacters(in: .whitespaces)
                try await ProfileManager.update(profile)
                if isContentChanged, isContentLoaded {
                    try profile.write(configContent)
                }
                await MainActor.run {
                    isSaving = false
                    onSaved?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func saveContentOnly() {
        if let err = validateConfigJSON(configContent) {
            errorMessage = err
            showError = true
            return
        }
        Task {
            do {
                try profile.write(configContent)
                await MainActor.run {
                    isContentChanged = false
                    showContentEditor = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "保存配置失败：\(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

struct ConfigContentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var content: String
    @Binding var isChanged: Bool
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("编辑配置内容 (JSON)")
                    .font(.headline)
                Spacer()
                Button("保存") {
                    isChanged = true
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled(true)
                .textContentType(nil)
                .padding(8)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Servers editor (offline)

private struct ProfileServersEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: Profile
    var onSaved: (() -> Void)?

    @State private var servers: [ShadowsocksServer] = []
    @State private var proxyDefaultTag: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var editingServer: ShadowsocksServer?
    @State private var showAddServer = false
    @State private var testStates: [String: ServerTestState] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("编辑服务器")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("节点（shadowsocks）")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("新增") { showAddServer = true }
                                .buttonStyle(.bordered)
                        }

                        if servers.isEmpty {
                            Text("暂无服务器。至少需要 1 个节点。")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        } else {
                            List {
                                ForEach(servers) { s in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.tag)
                                                .font(.system(.body, design: .monospaced))
                                            Text("\(s.server):\(s.serverPort) · \(s.method)")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()

                                        serverTestBadge(for: s)

                                        Button("测试") {
                                            Task { await testServer(s) }
                                        }
                                        .buttonStyle(.bordered)

                                        Button {
                                            editingServer = s
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .buttonStyle(.plain)
                                        .help("编辑")

                                        Button(role: .destructive) {
                                            deleteServer(tag: s.tag)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除")
                                    }
                                }
                            }
                            .frame(minHeight: 200)
                        }
                    }
                    .padding(10)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("默认服务器（proxy selector）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if servers.isEmpty {
                            Text("请先新增至少一个服务器。")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("proxy 默认节点", selection: $proxyDefaultTag) {
                                ForEach(servers) { s in
                                    Text(s.tag).tag(s.tag)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Text("说明：这里修改的是配置文件中 `outbounds` 的 `selector(tag=proxy).default`。连接后「出站组」切换是运行时行为。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("重置运行时缓存（删除 cache.db）") {
                            resetCacheDB()
                        }
                        .buttonStyle(.bordered)
                        .help("如果连接后仍然总是选到旧节点，可能是 sing-box cache_file 记住了上次选择。")
                    }
                    .padding(10)
                }

                HStack {
                    Button("保存") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || servers.isEmpty || proxyDefaultTag.isEmpty)

                    if isSaving { ProgressView().scaleEffect(0.8) }
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 560)
        .onAppear { load() }
        .sheet(item: $editingServer) { s in
            ShadowsocksServerEditorSheet(
                title: "编辑服务器",
                initial: s,
                existingTags: Set(servers.map { $0.tag }),
                onSave: { updated in
                    upsert(updated)
                    editingServer = nil
                }
            )
        }
        .sheet(isPresented: $showAddServer) {
            ShadowsocksServerEditorSheet(
                title: "新增服务器",
                initial: ShadowsocksServer(tag: suggestTag(), server: "", serverPort: 10086, method: "aes-256-gcm", password: ""),
                existingTags: Set(servers.map { $0.tag }),
                onSave: { created in
                    upsert(created)
                    if proxyDefaultTag.isEmpty { proxyDefaultTag = created.tag }
                    showAddServer = false
                }
            )
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func load() {
        guard isLoading else { return }
        Task {
            do {
                let content = try profile.read()
                let parsed = try ProfileServersCodec.decode(from: content)
                await MainActor.run {
                    servers = parsed.servers
                    proxyDefaultTag = parsed.proxyDefaultTag ?? (parsed.servers.first?.tag ?? "")
                    if !servers.contains(where: { $0.tag == proxyDefaultTag }) {
                        proxyDefaultTag = servers.first?.tag ?? ""
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "读取配置失败：\(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                let current = try profile.read()
                let updated = try ProfileServersCodec.apply(
                    to: current,
                    servers: servers,
                    proxyDefaultTag: proxyDefaultTag
                )
                try profile.write(updated)
                resetCacheDBIfExists()
                await MainActor.run {
                    isSaving = false
                    onSaved?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "保存失败：\(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func upsert(_ s: ShadowsocksServer) {
        if let idx = servers.firstIndex(where: { $0.tag == s.tag }) {
            servers[idx] = s
        } else {
            servers.append(s)
            servers.sort { $0.tag < $1.tag }
        }
        if proxyDefaultTag.isEmpty || !servers.contains(where: { $0.tag == proxyDefaultTag }) {
            proxyDefaultTag = servers.first?.tag ?? ""
        }
    }

    private func deleteServer(tag: String) {
        servers.removeAll { $0.tag == tag }
        testStates.removeValue(forKey: tag)
        if proxyDefaultTag == tag {
            proxyDefaultTag = servers.first?.tag ?? ""
        }
    }

    private func suggestTag() -> String {
        let existing = Set(servers.map { $0.tag })
        for i in 1...99 {
            let t = "ss\(i)"
            if !existing.contains(t) { return t }
        }
        return UUID().uuidString.prefix(8).description
    }

    private func resetCacheDB() {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName) else {
            errorMessage = "无法访问 App Group 容器（\(FilePath.groupName)）"
            showError = true
            return
        }
        let cacheDBURL = groupURL.appendingPathComponent("cache.db", isDirectory: false)
        guard fileManager.fileExists(atPath: cacheDBURL.path) else {
            errorMessage = "未找到 cache.db：\(cacheDBURL.path)"
            showError = true
            return
        }
        do {
            try fileManager.removeItem(at: cacheDBURL)
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
            showError = true
        }
    }

    private func resetCacheDBIfExists() {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName) else { return }
        let cacheDBURL = groupURL.appendingPathComponent("cache.db", isDirectory: false)
        guard fileManager.fileExists(atPath: cacheDBURL.path) else { return }
        try? fileManager.removeItem(at: cacheDBURL)
    }

    private func serverTestBadge(for s: ShadowsocksServer) -> some View {
        let state = testStates[s.tag] ?? .idle
        switch state {
        case .idle:
            return AnyView(EmptyView())
        case .testing:
            return AnyView(Text("测试中").font(.footnote).foregroundStyle(.secondary))
        case .success(let ms):
            return AnyView(Text("OK \(ms)ms").font(.footnote).foregroundStyle(.secondary))
        case .failure:
            return AnyView(Text("失败").font(.footnote).foregroundStyle(.secondary))
        }
    }

	private func testServer(_ s: ShadowsocksServer) async {
	    await MainActor.run { testStates[s.tag] = .testing }
	    let result = await testTCP(host: s.server, port: s.serverPort, timeoutSeconds: 2.0)
	    await MainActor.run {
	        switch result {
	        case .success(let ms): testStates[s.tag] = .success(ms)
	        case .failure(let err):
	            let msg = err.localizedDescription
	            testStates[s.tag] = .failure(msg)
	            errorMessage = "测试失败（\(s.tag)）：\(msg)"
	            showError = true
	        }
	    }
	}
}

private enum ServerTestState: Equatable {
    case idle
    case testing
    case success(Int)
    case failure(String)
}

private func testTCP(host: String, port: Int, timeoutSeconds: Double) async -> Result<Int, Error> {
    let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    func fail(_ message: String) -> Result<Int, Error> {
        .failure(NSError(domain: "com.meshflux.server-test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
    }
    guard !host.isEmpty else { return fail("empty host") }
    guard (1...65535).contains(port) else { return fail("invalid port") }
    guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return fail("invalid port") }

    return await withCheckedContinuation { cont in
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "com.meshflux.server-test.\(UUID().uuidString)")
        let start = Date()
        final class FinishOnce: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            private let connection: NWConnection
            private let cont: CheckedContinuation<Result<Int, Error>, Never>

            init(connection: NWConnection, cont: CheckedContinuation<Result<Int, Error>, Never>) {
                self.connection = connection
                self.cont = cont
            }

            func finish(_ result: Result<Int, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                cont.resume(returning: result)
            }
        }
        let finisher = FinishOnce(connection: connection, cont: cont)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                finisher.finish(.success(ms))
            case .failed(let error):
                finisher.finish(.failure(error))
            case .waiting(let error):
                finisher.finish(.failure(error))
            default:
                break
            }
        }

        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeoutSeconds) {
            finisher.finish(
                .failure(
                    NSError(
                        domain: "com.meshflux.server-test",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "timeout"]
                    )
                )
            )
        }
	}
}

private struct ShadowsocksServer: Identifiable, Hashable {
    var id: String { tag }
    var tag: String
    var server: String
    var serverPort: Int
    var method: String
    var password: String
}

private struct ShadowsocksServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initial: ShadowsocksServer
    let existingTags: Set<String>
    let onSave: (ShadowsocksServer) -> Void

    @State private var tag: String
    @State private var server: String
    @State private var portText: String
    @State private var method: String
    @State private var password: String

    @State private var errorMessage: String?
    @State private var showError = false

    init(title: String, initial: ShadowsocksServer, existingTags: Set<String>, onSave: @escaping (ShadowsocksServer) -> Void) {
        self.title = title
        self.initial = initial
        self.existingTags = existingTags
        self.onSave = onSave
        _tag = State(initialValue: initial.tag)
        _server = State(initialValue: initial.server)
        _portText = State(initialValue: "\(initial.serverPort)")
        _method = State(initialValue: initial.method)
        _password = State(initialValue: initial.password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Form {
                TextField("tag", text: $tag)
                TextField("server", text: $server)
                TextField("server_port", text: $portText)
                    .textFieldStyle(.roundedBorder)
                Picker("method", selection: $method) {
                    ForEach(SingboxConfigStore.ServerConfig.supportedMethods, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                SecureField("password", text: $password)
            }
            .formStyle(.grouped)

            HStack {
                Button("保存") { doSave() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func doSave() {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            errorMessage = "tag 不能为空"
            showError = true
            return
        }
        if t != initial.tag, existingTags.contains(t) {
            errorMessage = "tag 已存在：\(t)"
            showError = true
            return
        }
        let host = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            errorMessage = "server 不能为空"
            showError = true
            return
        }
        guard let port = Int(portText), (1...65535).contains(port) else {
            errorMessage = "server_port 必须是 1-65535"
            showError = true
            return
        }
        let m = method.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty {
            errorMessage = "method 不能为空"
            showError = true
            return
        }
        onSave(ShadowsocksServer(tag: t, server: host, serverPort: port, method: m, password: password))
    }
}

private enum ProfileServersCodec {
    struct Decoded {
        var servers: [ShadowsocksServer]
        var proxyDefaultTag: String?
    }

    static func decode(from jsonText: String) throws -> Decoded {
        guard let data = jsonText.data(using: .utf8) else { throw NSError(domain: "codec", code: 1) }
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let config = obj as? [String: Any] else { throw NSError(domain: "codec", code: 2) }
        let outboundsAny = config["outbounds"] as? [Any] ?? []
        let outbounds = outboundsAny.compactMap { $0 as? [String: Any] }

        let selector = outbounds.first { ($0["type"] as? String) == "selector" && ($0["tag"] as? String) == "proxy" }
        let selectorServerTags = (selector?["outbounds"] as? [Any])?.compactMap { $0 as? String } ?? []
        let selectorTagSet = Set(selectorServerTags)

        var servers: [ShadowsocksServer] = []
        for o in outbounds {
            guard (o["type"] as? String) == "shadowsocks" else { continue }
            guard let tag = o["tag"] as? String else { continue }
            if !selectorTagSet.isEmpty, !selectorTagSet.contains(tag) { continue }
            let server = (o["server"] as? String) ?? ""
            let port = (o["server_port"] as? Int) ?? 0
            let method = (o["method"] as? String) ?? ""
            let password = (o["password"] as? String) ?? ""
            servers.append(ShadowsocksServer(tag: tag, server: server, serverPort: port, method: method, password: password))
        }
        servers.sort { $0.tag < $1.tag }

        let proxyDefault = selector?["default"] as? String
        return Decoded(servers: servers, proxyDefaultTag: proxyDefault)
    }

    static func apply(to jsonText: String, servers: [ShadowsocksServer], proxyDefaultTag: String) throws -> String {
        guard let data = jsonText.data(using: .utf8) else { throw NSError(domain: "codec", code: 10) }
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard var config = obj as? [String: Any] else { throw NSError(domain: "codec", code: 11) }

        var outboundsAny = config["outbounds"] as? [Any] ?? []
        var outbounds = outboundsAny.compactMap { $0 as? [String: Any] }

        let oldSelector = outbounds.first { ($0["type"] as? String) == "selector" && ($0["tag"] as? String) == "proxy" }
        let oldTags = (oldSelector?["outbounds"] as? [Any])?.compactMap { $0 as? String } ?? []
        let oldTagSet = Set(oldTags)

        // Remove shadowsocks outbounds that belong to proxy selector (or all shadowsocks if selector absent).
        outbounds.removeAll { o in
            guard (o["type"] as? String) == "shadowsocks" else { return false }
            guard let tag = o["tag"] as? String else { return false }
            if oldTagSet.isEmpty { return true }
            return oldTagSet.contains(tag)
        }

        // Add/update shadowsocks servers.
        for s in servers {
            outbounds.append([
                "type": "shadowsocks",
                "tag": s.tag,
                "server": s.server,
                "server_port": s.serverPort,
                "method": s.method,
                "password": s.password
            ])
        }

        // Ensure proxy selector exists and references all server tags.
        let serverTags = servers.map { $0.tag }
        if let selectorIdx = outbounds.firstIndex(where: { ($0["type"] as? String) == "selector" && ($0["tag"] as? String) == "proxy" }) {
            var selector = outbounds[selectorIdx]
            selector["outbounds"] = serverTags
            selector["default"] = proxyDefaultTag
            outbounds[selectorIdx] = selector
        } else {
            outbounds.append([
                "type": "selector",
                "tag": "proxy",
                "outbounds": serverTags,
                "default": proxyDefaultTag
            ])
        }

        outboundsAny = outbounds
        config["outbounds"] = outboundsAny

        // Keep proxy server addresses excluded from tun routing to prevent loops (best-effort; IP literals only).
        if var inboundsAny = config["inbounds"] as? [Any] {
            var inbounds = inboundsAny.compactMap { $0 as? [String: Any] }
            if let tunIdx = inbounds.firstIndex(where: { ($0["type"] as? String) == "tun" }) {
                var tun = inbounds[tunIdx]
                var exclude = (tun["route_exclude_address"] as? [Any])?.compactMap { $0 as? String } ?? []
                var excludeSet = Set(exclude)
                for s in servers {
                    let addr = s.server.trimmingCharacters(in: .whitespacesAndNewlines)
                    if IPv4Address(addr) != nil {
                        let cidr = "\(addr)/32"
                        if !excludeSet.contains(cidr) {
                            exclude.insert(cidr, at: 0)
                            excludeSet.insert(cidr)
                        }
                    } else if IPv6Address(addr) != nil {
                        let cidr = "\(addr)/128"
                        if !excludeSet.contains(cidr) {
                            exclude.insert(cidr, at: 0)
                            excludeSet.insert(cidr)
                        }
                    }
                }
                tun["route_exclude_address"] = exclude
                inbounds[tunIdx] = tun
                inboundsAny = inbounds
                config["inbounds"] = inboundsAny
            }
        }

        let outData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: outData, as: UTF8.self)
    }
}
