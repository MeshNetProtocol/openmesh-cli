//
//  DefaultProfileHelper.swift
//  VPNLibrary
//
//  从 bundle 的 default_profile.json 创建并安装默认配置（规则 + 服务器模板）。
//  用于：首次启动自动安装、或配置列表为空时。Mac 与 iOS 共用。
//

import Foundation

public enum DefaultProfileHelper {
    /// 从 bundle 的 default_profile.json 创建一条「官方供应商」Profile 并设为当前选中。
    /// 若配置列表非空则直接返回 nil，不安装。
    /// - Returns: 创建成功的 Profile，失败或列表非空时返回 nil。
    public static func installDefaultProfileFromBundle() async throws -> Profile? {
        let list = try await ProfileManager.list()
        guard list.isEmpty else { return nil }

        #if os(macOS)
        guard FilePath.sharedDirectory != nil else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 不可用，请确认主程序已启用 App Group 能力（group.com.meshnetprotocol.OpenMesh）。"])
        }
        #endif

        guard let url = Bundle.main.url(forResource: "default_profile", withExtension: "json")
            ?? Bundle.main.url(forResource: "default_profile", withExtension: "json", subdirectory: "MeshFluxMac"),
              let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }

        let providerID = "official-local"
        let providerDir = FilePath.providerDirectory(providerID: providerID)
        do {
            try FileManager.default.createDirectory(at: providerDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw NSError(domain: "com.meshflux", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "无法创建配置目录：\(error.localizedDescription)",
                NSFilePathErrorKey: providerDir.path,
                NSUnderlyingErrorKey: error as NSError,
            ])
        }

        let configURL = FilePath.providerConfigFile(providerID: providerID)
        do {
            try data.write(to: configURL, options: [.atomic])
        } catch {
            throw NSError(domain: "com.meshflux", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "无法写入默认配置：\(error.localizedDescription)。请确认对 App Group 目录有写权限。",
                NSFilePathErrorKey: configURL.path,
                NSUnderlyingErrorKey: error as NSError,
            ])
        }

        let profile = Profile(
            name: "官方供应商",
            type: .local,
            path: configURL.path
        )
        do {
            try await ProfileManager.create(profile)
        } catch {
            throw NSError(domain: "com.meshflux", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "无法保存配置到数据库：\(error.localizedDescription)。若 extension 正在运行可先断开 VPN 后重试。",
                NSUnderlyingErrorKey: error as NSError,
            ])
        }
        await SharedPreferences.selectedProfileID.set(profile.mustID)

        var profileToProvider = await SharedPreferences.installedProviderIDByProfile.get()
        profileToProvider[String(profile.mustID)] = providerID
        await SharedPreferences.installedProviderIDByProfile.set(profileToProvider)

        var providerHashMap = await SharedPreferences.installedProviderPackageHash.get()
        providerHashMap[providerID] = "bundled"
        await SharedPreferences.installedProviderPackageHash.set(providerHashMap)

        return profile
    }

    /// 若配置列表为空则安装默认配置；若列表非空但 selectedProfileID 无效则选中第一项。与 Mac ensureDefaultProfileIfNeeded 一致。
    public static func ensureDefaultProfileIfNeeded() async {
        do {
            let installed = try await installDefaultProfileFromBundle()
            if installed != nil { return }
            let list = try? await ProfileManager.list()
            let id = await SharedPreferences.selectedProfileID.get()
            if id < 0, let list = list, !list.isEmpty {
                await SharedPreferences.selectedProfileID.set(list[0].mustID)
            }

            // One-time friendly rename for legacy installs: "默认配置" -> "官方供应商".
            // Keep it conservative to avoid renaming user-created profiles.
            if let list, list.count == 1 {
                let p = list[0]
                if p.name == "默认配置", p.type == .local, (p.remoteURL?.isEmpty ?? true) {
                    p.name = "官方供应商"
                    try? await ProfileManager.update(p)
                }
            }
        } catch {
            // 忽略；用户可在设置中手动添加或重试
        }
    }
}
