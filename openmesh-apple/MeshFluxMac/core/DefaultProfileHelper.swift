//
//  DefaultProfileHelper.swift
//  MeshFluxMac
//
//  从 bundle 的 default_profile.json 创建并安装默认配置（规则 + 服务器模板）。
//  用于：首次启动自动安装、或用户在「配置列表」为空时点击「使用默认配置」。
//

import Foundation
import VPNLibrary

enum DefaultProfileHelper {
    /// 从 bundle 的 default_profile.json 创建一条「默认配置」Profile 并设为当前选中。
    /// - Returns: 创建成功的 Profile，失败返回 nil。
    static func installDefaultProfileFromBundle() async throws -> Profile? {
        let list = try await ProfileManager.list()
        guard list.isEmpty else { return nil }

        guard FilePath.sharedDirectory != nil else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 不可用，请确认主程序已启用 App Group 能力（group.com.meshnetprotocol.OpenMesh）。"])
        }

        guard let url = Bundle.main.url(forResource: "default_profile", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            return nil
        }

        let nextId = try await ProfileManager.nextID()
        let configsDir = FilePath.configsDirectory
        do {
            try FileManager.default.createDirectory(at: configsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw NSError(domain: "com.meshflux", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "无法创建配置目录：\(error.localizedDescription)",
                NSFilePathErrorKey: configsDir.path,
                NSUnderlyingErrorKey: error as NSError,
            ])
        }

        let configURL = configsDir.appendingPathComponent("config_\(nextId).json")
        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw NSError(domain: "com.meshflux", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "无法写入默认配置：\(error.localizedDescription)。请确认对 App Group 目录有写权限。",
                NSFilePathErrorKey: configURL.path,
                NSUnderlyingErrorKey: error as NSError,
            ])
        }

        let profile = Profile(
            name: "默认配置",
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
        return profile
    }
}
