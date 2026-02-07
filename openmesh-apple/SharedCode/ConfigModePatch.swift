//
//  ConfigModePatch.swift
//  SharedCode
//
//  Raw profile mode:
//  - Keep profile content as the source of truth for route/dns behavior.
//  - Do not inject rule/global mode-specific route or DNS mutations.
//

import Foundation

private let configModePatchVersion = "2026-02-04-raw-profile-mode-1"

// MARK: - App Group IDs (shared)

// Keep these as top-level constants so they are visible across targets that compile SharedCode.
// NOTE: Avoid moving this into a new file unless you also update Xcode target memberships.
var appGroupMain: String { "group.com.meshnetprotocol.OpenMesh" }
var appGroupMacSys: String { "group.com.meshnetprotocol.OpenMesh.macsys" }

/// Applies raw-profile handling to a sing-box config JSON string. Returns patched JSON or original on parse/serialize error.
/// - Parameter content: Full sing-box config JSON string.
/// - Parameter isGlobalMode: Kept for compatibility and logging only.
public func applyRoutingModeToConfigContent(_ content: String, isGlobalMode: Bool) -> String {
    guard let data = content.data(using: .utf8),
          var config = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] else {
        NSLog("MeshFlux ConfigModePatch v%@ parse failed (isGlobalMode=%d)", configModePatchVersion, isGlobalMode ? 1 : 0)
        return content
    }
    applyRoutingModeToConfig(&config, isGlobalMode: isGlobalMode)
    logConfigModePatchState(config, isGlobalMode: isGlobalMode)
    writeConfigModePatchStateFile(config, isGlobalMode: isGlobalMode)
    guard let out = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) else {
        NSLog("MeshFlux ConfigModePatch v%@ serialize failed (isGlobalMode=%d)", configModePatchVersion, isGlobalMode ? 1 : 0)
        return content
    }
    return String(decoding: out, as: UTF8.self)
}

/// Raw profile mode: do not rewrite route/dns based on app mode.
/// - Parameter config: Parsed config as [String: Any] (e.g. from JSON).
/// - Parameter isGlobalMode: Kept for compatibility and logging only.
/// - Returns: The same config without route/dns mutations.
public func applyRoutingModeToConfig(_ config: inout [String: Any], isGlobalMode: Bool) {
    _ = config
    NSLog(
        "MeshFlux ConfigModePatch v%@ raw profile mode active (isGlobalMode=%d ignored)",
        configModePatchVersion,
        isGlobalMode ? 1 : 0
    )
}

// MARK: - State logging fields

private let geositeGeolocationCNTag = "geosite-geolocation-cn"
private let geositeGeolocationCNURL = "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs"

private func logConfigModePatchState(_ config: [String: Any], isGlobalMode: Bool) {
    let route = config["route"] as? [String: Any]
    let dns = config["dns"] as? [String: Any]

    let routeFinal = (route?["final"] as? String) ?? "nil"
    let dnsFinal = (dns?["final"] as? String) ?? "nil"

    let ruleSets = (route?["rule_set"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    let ruleSetTags = ruleSets.compactMap { $0["tag"] as? String }.sorted()
    let hasGeositeRuleSet = ruleSetTags.contains(geositeGeolocationCNTag)

    let routeRules = (route?["rules"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    let hasGeositeRouteRule = routeRules.contains { ($0["rule_set"] as? String) == geositeGeolocationCNTag }

    let dnsRules = (dns?["rules"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    let hasGeositeDNSRule = dnsRules.contains { ($0["rule_set"] as? String) == geositeGeolocationCNTag }
    let hasLegacyDomainSuffixCNRule = dnsRules.contains { ($0["domain_suffix"] as? [String])?.contains(".cn") == true }

    let msg = String(
        format: "MeshFlux ConfigModePatch v%@ profile_only=1 route.final=%@ dns.final=%@ rule_sets=%@ geosite.rule_set=%d geosite.route_rule=%d geosite.dns_rule=%d legacy.cn_suffix=%d mode_arg_ignored=%d",
        configModePatchVersion,
        routeFinal,
        dnsFinal,
        String(describing: ruleSetTags),
        hasGeositeRuleSet ? 1 : 0,
        hasGeositeRouteRule ? 1 : 0,
        hasGeositeDNSRule ? 1 : 0,
        hasLegacyDomainSuffixCNRule ? 1 : 0,
        isGlobalMode ? 1 : 0
    )
    NSLog(
        "MeshFlux ConfigModePatch v%@ profile_only=1 route.final=%@ dns.final=%@ rule_sets=%@ geosite.rule_set=%d geosite.route_rule=%d geosite.dns_rule=%d legacy.cn_suffix=%d mode_arg_ignored=%d",
        configModePatchVersion,
        routeFinal,
        dnsFinal,
        String(describing: ruleSetTags),
        hasGeositeRuleSet ? 1 : 0,
        hasGeositeRouteRule ? 1 : 0,
        hasGeositeDNSRule ? 1 : 0,
        hasLegacyDomainSuffixCNRule ? 1 : 0,
        isGlobalMode ? 1 : 0
    )
    emitPatchMarkerToStderr(msg)
}

private func writeConfigModePatchStateFile(_ config: [String: Any], isGlobalMode: Bool) {
    let fileManager = FileManager.default
    let appGroupID = (Bundle.main.bundleIdentifier?.hasSuffix(".macsys") == true) ? appGroupMacSys : appGroupMain
    guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
        NSLog("MeshFlux ConfigModePatch v%@ app group unavailable (appGroupID=%@)", configModePatchVersion, appGroupID)
        return
    }

    let cacheDir = groupURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)
    let outURL = cacheDir.appendingPathComponent("meshflux_config_mode_patch_state.json", isDirectory: false)

    let route = config["route"] as? [String: Any]
    let dns = config["dns"] as? [String: Any]
    let ruleSets = (route?["rule_set"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    let ruleSetTags = ruleSets.compactMap { $0["tag"] as? String }.sorted()
    let hasGeositeRuleSet = ruleSetTags.contains(geositeGeolocationCNTag)
    let dnsRules = (dns?["rules"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    let hasGeositeDNSRule = dnsRules.contains { ($0["rule_set"] as? String) == geositeGeolocationCNTag }

    let obj: [String: Any] = [
        "version": configModePatchVersion,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "profile_only": true,
        "mode_arg_ignored": isGlobalMode,
        "app_group_id": appGroupID,
        "route_final": (route?["final"] as? String) ?? NSNull(),
        "dns_final": (dns?["final"] as? String) ?? NSNull(),
        "route_rule_set_tags": ruleSetTags,
        "has_geosite_geolocation_cn_rule_set": hasGeositeRuleSet,
        "has_geosite_geolocation_cn_dns_rule": hasGeositeDNSRule,
        "geosite_geolocation_cn_url": geositeGeolocationCNURL
    ]

    do {
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outURL, options: [.atomic])
        NSLog("MeshFlux ConfigModePatch v%@ wrote state: %@", configModePatchVersion, outURL.path)
        emitPatchMarkerToStderr("MeshFlux ConfigModePatch wrote state: \(outURL.path)")
    } catch {
        NSLog("MeshFlux ConfigModePatch v%@ write state failed: %@", configModePatchVersion, String(describing: error))
        emitPatchMarkerToStderr("MeshFlux ConfigModePatch write state failed: \(String(describing: error))")
    }
}

private func emitPatchMarkerToStderr(_ message: String) {
    let line = message.hasSuffix("\n") ? message : (message + "\n")
    guard let data = line.data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
}
