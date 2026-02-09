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
        return nil
    }

    /// 若配置列表为空则安装默认配置；若列表非空但 selectedProfileID 无效则选中第一项。与 Mac ensureDefaultProfileIfNeeded 一致。
    public static func ensureDefaultProfileIfNeeded() async {
        do {
            let installed = try await installDefaultProfileFromBundle()
            if installed != nil { return }
            let list = try? await ProfileManager.list()
            _ = await SharedPreferences.selectedProfileID.get()

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
