//
//  ImportProfileView.swift
//  MeshFluxMac
//
//  从 URL 或本地文件导入 sing-box 配置，创建新 Profile。与 sing-box ImportProfileView 行为一致。
//

import SwiftUI
import UniformTypeIdentifiers
import VPNLibrary

struct ImportProfileView: View {
    @Environment(\.dismiss) private var dismiss

    var onImported: (() -> Void)?

    @State private var importURLString: String = ""
    @State private var profileName: String = "导入的配置"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showFilePicker = false
    @State private var importedContent: String?
    @State private var importSource: ImportSource?

    private enum ImportSource {
        case url(String)
        case file(URL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("导入配置")
                .font(.headline)

            // 从 URL 导入
            VStack(alignment: .leading, spacing: 8) {
                Text("从 URL 导入")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/config.json", text: $importURLString)
                    .textFieldStyle(.roundedBorder)
                Button {
                    fetchFromURL()
                } label: {
                    Label("获取并导入", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(importURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }

            Divider()

            // 从文件导入
            VStack(alignment: .leading, spacing: 8) {
                Text("从本地文件导入")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showFilePicker = true
                } label: {
                    Label("选择 JSON 文件...", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            if importedContent != nil {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("配置名称")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("配置名称", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        createProfileFromImported()
                    } label: {
                        Label("创建配置", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json, .text],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else {
                        errorMessage = "无法访问所选文件"
                        showError = true
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        guard let text = String(data: data, encoding: .utf8) else {
                            errorMessage = "文件编码不支持"
                            showError = true
                            return
                        }
                        if validateJSON(text) {
                            let name = url.deletingPathExtension().lastPathComponent
                            importedContent = text
                            if profileName.isEmpty || profileName == "导入的配置" {
                                profileName = name
                            }
                            importSource = .file(url)
                        } else {
                            errorMessage = "不是有效的 JSON 配置"
                            showError = true
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func fetchFromURL() {
        let urlString = importURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            errorMessage = "请输入有效 URL"
            showError = true
            return
        }
        isLoading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    await MainActor.run {
                        errorMessage = "响应编码不支持"
                        showError = true
                        isLoading = false
                    }
                    return
                }
                guard validateJSON(text) else {
                    await MainActor.run {
                        errorMessage = "URL 返回的不是有效 JSON 配置"
                        showError = true
                        isLoading = false
                    }
                    return
                }
                await MainActor.run {
                    importedContent = text
                    importSource = .url(urlString)
                    if profileName.isEmpty || profileName == "导入的配置" {
                        profileName = url.deletingPathExtension().lastPathComponent
                        if profileName.isEmpty { profileName = "导入的配置" }
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }

    private func createProfileFromImported() {
        guard let content = importedContent else { return }
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isLoading = true
        Task {
            do {
                let nextId = try await ProfileManager.nextID()
                let configsDir = FilePath.configsDirectory
                try FileManager.default.createDirectory(at: configsDir, withIntermediateDirectories: true)
                let configURL = configsDir.appendingPathComponent("config_\(nextId).json")
                try content.write(to: configURL, atomically: true, encoding: .utf8)

                let profile = Profile(
                    name: name,
                    type: .local,
                    path: configURL.path
                )
                try await ProfileManager.create(profile)
                await SharedPreferences.selectedProfileID.set(profile.mustID)
                await MainActor.run {
                    isLoading = false
                    onImported?()
                    NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }

    /// 校验为合法 JSON（sing-box 配置为 JSON object）。
    private func validateJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              obj is [String: Any] else {
            return false
        }
        return true
    }
}
