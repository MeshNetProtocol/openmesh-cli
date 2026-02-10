import Foundation
import VPNLibrary

enum ProviderUninstallStep: String, CaseIterable, Identifiable {
    case validate
    case removeProfile
    case removePreferences
    case removeFiles
    case finalize

    var id: ProviderUninstallStep { self }
}

enum ProviderUninstaller {
    static func uninstall(
        providerID: String,
        vpnConnected: Bool,
        progress: (@Sendable (ProviderUninstallStep, String) -> Void)?
    ) async throws {
        let id = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw NSError(domain: "ProviderUninstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "provider_id 不能为空"])
        }

        progress?(.validate, "检查当前连接状态")
        let selectedProfileID = await SharedPreferences.selectedProfileID.get()
        let mapping = await SharedPreferences.installedProviderIDByProfile.get()
        var profileIDSet = Set(mapping.compactMap { (k, v) -> Int64? in
            guard v == id else { return nil }
            return Int64(k)
        })

        let profiles = try await ProfileManager.list()
        for profile in profiles {
            guard let profileID = profile.id else { continue }
            guard profileBelongsToProvider(profile.path, providerID: id) else { continue }
            profileIDSet.insert(profileID)
        }
        let profileIDs = Array(profileIDSet)

        if vpnConnected, profileIDs.contains(selectedProfileID) {
            throw NSError(domain: "ProviderUninstaller", code: 2, userInfo: [NSLocalizedDescriptionKey: "当前 profile 正在被使用，请先断开 VPN 再卸载"])
        }

        progress?(.removeProfile, "删除 Profile 记录")
        for pid in profileIDs {
            if let profile = try await ProfileManager.get(pid) {
                try await ProfileManager.delete(profile)
            }
        }

        if !profileIDs.isEmpty, profileIDs.contains(selectedProfileID) {
            let list = try await ProfileManager.list()
            if let first = list.first {
                await SharedPreferences.selectedProfileID.set(first.mustID)
            } else {
                await SharedPreferences.selectedProfileID.set(-1)
            }
        }

        progress?(.removePreferences, "清理偏好映射")
        if !profileIDs.isEmpty {
            var outboundByProfile = await SharedPreferences.selectedOutboundTagByProfile.get()
            for pid in profileIDs {
                outboundByProfile.removeValue(forKey: String(pid))
            }
            await SharedPreferences.selectedOutboundTagByProfile.set(outboundByProfile)
        }

        var profileToProvider = await SharedPreferences.installedProviderIDByProfile.get()
        for pid in profileIDs {
            profileToProvider.removeValue(forKey: String(pid))
        }
        await SharedPreferences.installedProviderIDByProfile.set(profileToProvider)

        var hashByProvider = await SharedPreferences.installedProviderPackageHash.get()
        hashByProvider.removeValue(forKey: id)
        await SharedPreferences.installedProviderPackageHash.set(hashByProvider)

        var pendingByProvider = await SharedPreferences.installedProviderPendingRuleSetTags.get()
        pendingByProvider.removeValue(forKey: id)
        await SharedPreferences.installedProviderPendingRuleSetTags.set(pendingByProvider)

        var ruleSetURLByProvider = await SharedPreferences.installedProviderRuleSetURLByProvider.get()
        ruleSetURLByProvider.removeValue(forKey: id)
        await SharedPreferences.installedProviderRuleSetURLByProvider.set(ruleSetURLByProvider)

        progress?(.removeFiles, "删除 App Group 缓存文件")
        try removeProviderFiles(providerID: id)
        progress?(.finalize, "完成")
    }

    private static func profileBelongsToProvider(_ path: String?, providerID: String) -> Bool {
        guard let path, !path.isEmpty else { return false }
        let marker = "/providers/\(providerID)/"
        return path.contains(marker)
    }

    private static func removeProviderFiles(providerID: String) throws {
        let fm = FileManager.default
        let providerDir = FilePath.providerDirectory(providerID: providerID)
        if fm.fileExists(atPath: providerDir.path) {
            try fm.removeItem(at: providerDir)
        }

        let providersRoot = providerDir.deletingLastPathComponent()
        let stagingRoot = providersRoot.appendingPathComponent(".staging", isDirectory: true)
        let backupRoot = providersRoot.appendingPathComponent(".backup", isDirectory: true)
        for root in [stagingRoot, backupRoot] {
            guard fm.fileExists(atPath: root.path) else { continue }
            let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for u in items {
                let name = u.lastPathComponent
                if name == providerID || name.hasPrefix("\(providerID)-") {
                    try? fm.removeItem(at: u)
                }
            }
        }
    }
}
