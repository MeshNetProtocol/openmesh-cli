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
        guard let url = Bundle.main.url(forResource: "default_profile", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            return nil
        }
        let nextId = try await ProfileManager.nextID()
        let configsDir = FilePath.configsDirectory
        try FileManager.default.createDirectory(at: configsDir, withIntermediateDirectories: true)
        let configURL = configsDir.appendingPathComponent("config_\(nextId).json")
        try content.write(to: configURL, atomically: true, encoding: .utf8)
        let profile = Profile(
            name: "默认配置",
            type: .local,
            path: configURL.path
        )
        try await ProfileManager.create(profile)
        await SharedPreferences.selectedProfileID.set(profile.mustID)
        return profile
    }
}
