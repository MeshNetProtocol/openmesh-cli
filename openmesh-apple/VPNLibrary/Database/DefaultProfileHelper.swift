//
//  DefaultProfileHelper.swift
//  VPNLibrary
//
//  用于：首次启动选中配置（若有）、legacy 命名迁移。Mac 与 iOS 共用。
//

import Foundation

public enum DefaultProfileHelper {
    /// 若配置列表为空则提示用户手动添加；若列表非空但 selectedProfileID 无效则选中第一项。
    public static func ensureDefaultProfileIfNeeded() async {
        let list = try? await ProfileManager.list()
        let selectedID = await SharedPreferences.selectedProfileID.get()

        if let list, !list.isEmpty, selectedID == -1 {
            // If there are profiles but none selected, select the first one.
            if let first = list.first {
                await SharedPreferences.selectedProfileID.set(first.mustID)
            }
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
    }
}
