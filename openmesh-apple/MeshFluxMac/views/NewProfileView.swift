//
//  NewProfileView.swift
//  MeshFluxMac
//
//  新建配置：类型选 Local/Remote，与 sing-box NewProfileView 对齐。
//  Local 可选「新建空配置」或「从文件导入」；Remote 为 URL + 自动更新。
//

import SwiftUI
import UniformTypeIdentifiers
import VPNLibrary

struct NewProfileView: View {
    @Environment(\.dismiss) private var dismiss
    var onCreated: (() -> Void)?

    @State private var profileName: String = ""
    @State private var profileType: ProfileType = .local
    @State private var localCreateNew: Bool = true  // true = 新建空配置, false = 从文件导入
    @State private var localFileURL: URL?
    @State private var remoteURL: String = ""
    @State private var autoUpdate: Bool = false
    @State private var autoUpdateInterval: String = "60"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showFilePicker = false

    private var canCreate: Bool {
        let nameOk = !profileName.trimmingCharacters(in: .whitespaces).isEmpty
        switch profileType {
        case .local:
            return nameOk && (localCreateNew || localFileURL != nil)
        case .remote:
            return nameOk && !remoteURL.trimmingCharacters(in: .whitespaces).isEmpty
        case .icloud:
            return nameOk
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建配置")
                .font(.headline)

            TextField("配置名称", text: $profileName, prompt: Text("必填"))
                .textFieldStyle(.roundedBorder)

            Picker("类型", selection: $profileType) {
                Text("本地").tag(ProfileType.local)
                Text("远程 (URL)").tag(ProfileType.remote)
            }
            .pickerStyle(.segmented)

            if profileType == .local {
                Picker("文件", selection: $localCreateNew) {
                    Text("新建空配置").tag(true)
                    Text("从文件导入").tag(false)
                }
                .pickerStyle(.segmented)
                if !localCreateNew {
                    HStack {
                        Text("选择 JSON 文件")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(localFileURL?.lastPathComponent ?? "选择文件…") {
                            showFilePicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if profileType == .remote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("订阅/配置 URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("https://example.com/config.json", text: $remoteURL)
                        .textFieldStyle(.roundedBorder)
                    Toggle("自动更新", isOn: $autoUpdate)
                    if autoUpdate {
                        HStack {
                            Text("更新间隔（分钟）")
                            TextField("60", text: $autoUpdateInterval)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    createProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || isSaving)
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 320)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                _ = url.startAccessingSecurityScopedResource()
                localFileURL = url
            case .failure:
                break
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func createProfile() {
        guard canCreate else { return }
        isSaving = true
        Task {
            do {
                let nextId = try await ProfileManager.nextID()
                let configsDir = FilePath.configsDirectory
                try FileManager.default.createDirectory(at: configsDir, withIntermediateDirectories: true)
                let configURL = configsDir.appendingPathComponent("config_\(nextId).json")
                let name = profileName.trimmingCharacters(in: .whitespaces)

                switch profileType {
                case .local:
                    if localCreateNew {
                        let template = Self.defaultConfigContent()
                        try template.write(to: configURL, atomically: true, encoding: .utf8)
                    } else {
                        guard let fileURL = localFileURL else {
                            throw NSError(domain: "NewProfileView", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择要导入的文件"])
                        }
                        defer { fileURL.stopAccessingSecurityScopedResource() }
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        try content.write(to: configURL, atomically: true, encoding: .utf8)
                    }
                    let profile = Profile(
                        name: name,
                        type: .local,
                        path: configURL.path
                    )
                    try await ProfileManager.create(profile)
                    await SharedPreferences.selectedProfileID.set(profile.mustID)

                case .remote:
                    let urlString = remoteURL.trimmingCharacters(in: .whitespaces)
                    guard let url = URL(string: urlString) else {
                        throw NSError(domain: "NewProfileView", code: 2, userInfo: [NSLocalizedDescriptionKey: "请输入有效的 URL"])
                    }
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let content = String(data: data, encoding: .utf8) else {
                        throw NSError(domain: "NewProfileView", code: 3, userInfo: [NSLocalizedDescriptionKey: "URL 返回内容编码不支持"])
                    }
                    try content.write(to: configURL, atomically: true, encoding: .utf8)
                    let interval = Int32(autoUpdateInterval.trimmingCharacters(in: .whitespaces)) ?? 60
                    let profile = Profile(
                        name: name,
                        type: .remote,
                        path: configURL.path,
                        remoteURL: urlString,
                        autoUpdate: autoUpdate,
                        autoUpdateInterval: interval
                    )
                    try await ProfileManager.create(profile)
                    await SharedPreferences.selectedProfileID.set(profile.mustID)

                case .icloud:
                    // 暂不支持在新建时创建 iCloud 配置；可后续扩展
                    throw NSError(domain: "NewProfileView", code: 4, userInfo: [NSLocalizedDescriptionKey: "暂不支持新建 iCloud 配置"])
                }

                await MainActor.run {
                    isSaving = false
                    onCreated?()
                    NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
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

    private static func defaultConfigContent() -> String {
        if let url = Bundle.main.url(forResource: "default_profile", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return String(decoding: data, as: UTF8.self)
        }
        return """
        {
          "log": { "level": "info" },
          "inbounds": [{ "type": "tun", "tag": "tun-in" }],
          "outbounds": [
            { "type": "shadowsocks", "tag": "proxy", "server": "127.0.0.1", "server_port": 8388, "method": "aes-256-gcm", "password": "" },
            { "type": "direct", "tag": "direct" }
          ],
          "route": { "rules": [{ "action": "sniff" }], "final": "direct" }
        }
        """
    }
}
