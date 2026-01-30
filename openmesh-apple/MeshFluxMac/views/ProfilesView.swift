//
//  ProfilesView.swift
//  MeshFluxMac
//
//  Phase 3: Profile list + New Profile (local, configs/config_<id>.json).
//

import SwiftUI
import VPNLibrary

struct ProfilesView: View {
    @State private var profiles: [Profile] = []
    @State private var selectedProfileID: Int64 = -1
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var profileToEdit: Profile?
    @State private var profileToDelete: Profile?
    @State private var showDeleteConfirm = false
    @State private var isInstallingDefault = false
    @State private var showImportProfile = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    NewProfileView(onCreated: {
                        loadProfiles()
                        NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                    })
                } label: {
                    Label("新建配置", systemImage: "plus")
                        .foregroundStyle(Color.accentColor)
                }
                Button {
                    showImportProfile = true
                } label: {
                    Label("导入配置", systemImage: "square.and.arrow.down")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            if profiles.isEmpty {
                Section {
                    Text("暂无配置")
                        .foregroundStyle(.secondary)
                    Button {
                        installDefaultProfile()
                    } label: {
                        Label("使用默认配置", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isInstallingDefault)
                }
            } else {
                Section("配置") {
                    List(selection: $selectedProfileID) {
                        ForEach(profiles, id: \.mustID) { profile in
                            ProfileRowView(
                                profile: profile,
                                isSelected: selectedProfileID == profile.mustID,
                                onEdit: { profileToEdit = profile },
                                onDelete: {
                                    profileToDelete = profile
                                    showDeleteConfirm = true
                                }
                            )
                            .tag(profile.mustID)
                            .onTapGesture {
                                selectProfile(profile.mustID)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadProfiles()
        }
        .sheet(item: $profileToEdit) { profile in
            EditProfileView(profile: profile) {
                loadProfiles()
                NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
            }
        }
        .alert("删除配置", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {
                profileToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let p = profileToDelete { deleteProfile(p) }
                profileToDelete = nil
            }
        } message: {
            if let p = profileToDelete {
                Text("确定要删除配置「\(p.name)」吗？删除后无法恢复。")
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .sheet(isPresented: $showImportProfile) {
            ImportProfileView(onImported: {
                loadProfiles()
                NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
            })
        }
    }

    private func loadProfiles() {
        Task {
            do {
                let list = try await ProfileManager.list()
                let id = await SharedPreferences.selectedProfileID.get()
                await MainActor.run {
                    profiles = list
                    selectedProfileID = id
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func selectProfile(_ id: Int64) {
        Task {
            await SharedPreferences.selectedProfileID.set(id)
            await MainActor.run {
                selectedProfileID = id
            }
            NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
        }
    }

    /// 从 bundle 安装自带默认配置（规则 + 服务器模板），仅当当前没有任何配置时可用。
    private func installDefaultProfile() {
        isInstallingDefault = true
        Task {
            do {
                if let _ = try await DefaultProfileHelper.installDefaultProfileFromBundle() {
                    await MainActor.run {
                        loadProfiles()
                        isInstallingDefault = false
                    }
                    NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                } else {
                    await MainActor.run {
                        isInstallingDefault = false
                        errorMessage = "无法读取自带默认配置（default_profile.json）"
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isInstallingDefault = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func deleteProfile(_ profile: Profile) {
        Task {
            do {
                try await ProfileManager.delete(profile)
                if selectedProfileID == profile.mustID {
                    let list = try await ProfileManager.list()
                    if let first = list.first {
                        await SharedPreferences.selectedProfileID.set(first.mustID)
                        await MainActor.run { selectedProfileID = first.mustID }
                    } else {
                        await SharedPreferences.selectedProfileID.set(-1)
                        await MainActor.run { selectedProfileID = -1 }
                    }
                    NotificationCenter.default.post(name: .selectedProfileDidChange, object: nil)
                }
                await MainActor.run { loadProfiles() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct ProfileRowView: View {
    let profile: Profile
    let isSelected: Bool
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack {
            Text(profile.name)
                .font(.body)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
            Button {
                onEdit?()
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("编辑配置")
            Button {
                onDelete?()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("删除配置")
        }
        .padding(.vertical, 4)
    }
}
