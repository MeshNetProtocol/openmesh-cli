//
//  EditProfileView.swift
//  MeshFluxMac
//
//  Edit profile name and config content (JSON). Aligned with sing-box EditProfileView + EditProfileContentView.
//

import SwiftUI
import VPNLibrary

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
