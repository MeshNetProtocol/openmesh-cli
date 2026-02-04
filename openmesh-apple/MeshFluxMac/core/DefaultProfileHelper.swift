//
//  DefaultProfileHelper.swift
//  MeshFluxMac
//
//  委托 VPNLibrary.DefaultProfileHelper，仅增加 cfPrefsTrace。
//

import Foundation
import VPNLibrary

enum DefaultProfileHelper {
    /// 从 bundle 的 default_profile.json 创建一条「默认配置」Profile 并设为当前选中。
    /// - Returns: 创建成功的 Profile，失败返回 nil。
    static func installDefaultProfileFromBundle() async throws -> Profile? {
        cfPrefsTrace("DefaultProfileHelper.installDefaultProfileFromBundle start (will call VPNLibrary)")
        let profile = try await VPNLibrary.DefaultProfileHelper.installDefaultProfileFromBundle()
        if profile != nil {
            cfPrefsTrace("DefaultProfileHelper.installDefaultProfileFromBundle installed default profile")
        }
        return profile
    }
}
