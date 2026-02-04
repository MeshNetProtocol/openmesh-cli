//
//  ConfigModePatch.swift
//  SharedCode
//
//  Applies routing mode (rule vs global) to a sing-box config:
//  - Rule mode: only proxy-list domains → proxy + Google DNS; everything else → direct + local DNS. No geoip/geosite in route rules.
//  - Global mode: China (geoip-cn + geosite-geolocation-cn) → direct + local DNS; everything else → proxy + Google DNS.
//

import Foundation

private let configModePatchVersion = "2026-02-04-geosite-cn-verify-1"

/// Applies routing mode to a sing-box config JSON string. Returns patched JSON or original on parse/serialize error.
/// - Parameter content: Full sing-box config JSON string.
/// - Parameter isGlobalMode: true = global (geoip-cn direct, rest proxy); false = rule (only proxy-list proxy, rest direct).
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

/// Applies rule or global mode to a sing-box config dictionary (mutates in place).
/// - Parameter config: Parsed config as [String: Any] (e.g. from JSON).
/// - Parameter isGlobalMode: true = global (geoip-cn direct, rest proxy); false = rule (only proxy-list proxy, rest direct).
/// - Returns: The same config with route and dns sections updated for the given mode.
public func applyRoutingModeToConfig(_ config: inout [String: Any], isGlobalMode: Bool) {
    guard var route = config["route"] as? [String: Any] else { return }
    var routeRules: [[String: Any]] = (route["rules"] as? [Any])?
        .compactMap { $0 as? [String: Any] } ?? []

    if isGlobalMode {
        // Global: China (geoip-cn + geosite-geolocation-cn) → direct. Everything else → proxy.
        routeRules = buildGlobalModeRouteRules(from: routeRules)
        route["final"] = "proxy"
        ensureGeositeGeolocationCNRuleSet(&route)
    } else {
        // Rule: route.rules = sniff + only rules with outbound "proxy". No geoip/geosite. route.final = direct.
        // Also reject direct IPv6 to avoid "no route to host" on networks where IPv6 is unusable under tunnel routing.
        routeRules = buildRuleModeRouteRules(from: routeRules)
        route["final"] = "direct"
        removeRuleSet(&route, tag: geositeGeolocationCNTag)
    }

    route["rules"] = routeRules
    config["route"] = route

    // DNS by mode
    if var dns = config["dns"] as? [String: Any] {
        if isGlobalMode {
            dns["final"] = "google-dns"
            dns["rules"] = buildGlobalModeDNSRules()
        } else {
            dns["final"] = "local-dns"
            dns["strategy"] = "ipv4_only"
            let proxyDomains = extractProxyDomainsFromRouteRules(routeRules)
            dns["rules"] = buildRuleModeDNSRules(proxyDomains: proxyDomains)
        }
        config["dns"] = dns
    }

    // Force direct outbound to IPv4 only so geoip-cn/direct traffic does not try IPv6 (avoids "no route to host" on networks without usable IPv6).
    if var outbounds = config["outbounds"] as? [Any] {
        for i in outbounds.indices {
            guard var ob = outbounds[i] as? [String: Any],
                  ob["tag"] as? String == "direct" else { continue }
            ob["domain_strategy"] = "ipv4_only"
            outbounds[i] = ob
            break
        }
        config["outbounds"] = outbounds
    }
}

// MARK: - Route rules

private func buildGlobalModeRouteRules(from existing: [[String: Any]]) -> [[String: Any]] {
    var out: [[String: Any]] = []
    var hasSniff = false
    var nonSniffNonRoute: [[String: Any]] = [] // e.g. hijack-dns
    for rule in existing {
        if (rule["action"] as? String) == "sniff" {
            if !hasSniff {
                out.append(rule)
                hasSniff = true
            }
            continue
        }
        if (rule["action"] as? String) != nil && rule["outbound"] == nil {
            nonSniffNonRoute.append(rule)
            continue
        }
        // drop all other route rules; we only want sniff + geoip-cn + actions
    }
    if !hasSniff {
        out.append(["action": "sniff"])
    }
    // Prefer domain-based China matching when possible (sniffed domain / mapped domain), then fall back to geoip-cn (destination IP).
    // Reject China IPv6 quickly so clients can retry IPv4 (avoids "no route to host" on networks without usable direct IPv6).
    out.append(["rule_set": geositeGeolocationCNTag, "ip_version": 6, "action": "reject"])
    // When the tunnel installs ::/0, direct IPv6 dials from the provider can lose a usable route on the physical interface.
    // Reject geoip-cn IPv6 quickly so clients can retry IPv4 (keeps CN as "direct" when IPv4 is available).
    out.append(["rule_set": "geoip-cn", "ip_version": 6, "action": "reject"])
    out.append(["rule_set": geositeGeolocationCNTag, "outbound": "direct"])
    out.append(["rule_set": "geoip-cn", "outbound": "direct"])
    out.append(contentsOf: nonSniffNonRoute)
    return out
}

private func buildRuleModeRouteRules(from existing: [[String: Any]]) -> [[String: Any]] {
    var out: [[String: Any]] = []
    var hasSniff = false
    var nonSniffNonRoute: [[String: Any]] = [] // e.g. hijack-dns, to append after proxy rules
    for rule in existing {
        if (rule["action"] as? String) == "sniff" {
            if !hasSniff {
                out.append(rule)
                hasSniff = true
            }
            continue
        }
        if (rule["action"] as? String) != nil && rule["outbound"] == nil {
            nonSniffNonRoute.append(rule)
            continue
        }
        if (rule["rule_set"] as? String) == "geoip-cn" { continue }
        if (rule["rule_set"] as? String) == geositeGeolocationCNTag { continue }
        if rule["outbound"] as? String == "proxy" {
            out.append(rule)
        }
    }
    if !hasSniff {
        out.insert(["action": "sniff"], at: 0)
    }
    // Avoid direct IPv6 for non-proxy traffic (common cause: apps using cached AAAA / DoH outside our DNS module).
    out.append(["ip_version": 6, "action": "reject"])
    out.append(contentsOf: nonSniffNonRoute)
    return out
}

// MARK: - DNS rules

private func buildGlobalModeDNSRules() -> [[String: Any]] {
    // Global mode DNS:
    // - China domains → local-dns (and IPv4 only, to avoid unusable direct IPv6).
    // - Everything else → google-dns (dns.final).
    [
        [
            "action": "route",
            "rule_set": geositeGeolocationCNTag,
            "server": "local-dns",
            "strategy": "ipv4_only"
        ]
    ]
}

private func extractProxyDomainsFromRouteRules(_ rules: [[String: Any]]) -> (domain: [String], domainSuffix: [String]) {
    var domain: [String] = []
    var domainSuffix: [String] = []
    for rule in rules {
        guard rule["outbound"] as? String == "proxy" else { continue }
        if let v = rule["domain"] as? [String] { domain.append(contentsOf: v) }
        if let v = rule["domain_suffix"] as? [String] { domainSuffix.append(contentsOf: v) }
    }
    return (Array(Set(domain)).sorted(), Array(Set(domainSuffix)).sorted())
}

private func buildRuleModeDNSRules(proxyDomains: (domain: [String], domainSuffix: [String])) -> [[String: Any]] {
    var rules: [[String: Any]] = []
    if !proxyDomains.domain.isEmpty {
        rules.append([
            "action": "route",
            "domain": proxyDomains.domain,
            "server": "google-dns"
        ])
    }
    if !proxyDomains.domainSuffix.isEmpty {
        rules.append([
            "action": "route",
            "domain_suffix": proxyDomains.domainSuffix,
            "server": "google-dns"
        ])
    }
    return rules
}

// MARK: - Rule sets

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
        format: "MeshFlux ConfigModePatch v%@ mode=%@ route.final=%@ dns.final=%@ rule_sets=%@ geosite.rule_set=%d geosite.route_rule=%d geosite.dns_rule=%d legacy.cn_suffix=%d",
        configModePatchVersion,
        isGlobalMode ? "global" : "rule",
        routeFinal,
        dnsFinal,
        String(describing: ruleSetTags),
        hasGeositeRuleSet ? 1 : 0,
        hasGeositeRouteRule ? 1 : 0,
        hasGeositeDNSRule ? 1 : 0,
        hasLegacyDomainSuffixCNRule ? 1 : 0
    )
    NSLog(
        "MeshFlux ConfigModePatch v%@ mode=%@ route.final=%@ dns.final=%@ rule_sets=%@ geosite.rule_set=%d geosite.route_rule=%d geosite.dns_rule=%d legacy.cn_suffix=%d",
        configModePatchVersion,
        isGlobalMode ? "global" : "rule",
        routeFinal,
        dnsFinal,
        String(describing: ruleSetTags),
        hasGeositeRuleSet ? 1 : 0,
        hasGeositeRouteRule ? 1 : 0,
        hasGeositeDNSRule ? 1 : 0,
        hasLegacyDomainSuffixCNRule ? 1 : 0
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
        "mode": isGlobalMode ? "global" : "rule",
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

private func ensureGeositeGeolocationCNRuleSet(_ route: inout [String: Any]) {
    ensureRemoteRuleSet(
        &route,
        tag: geositeGeolocationCNTag,
        url: geositeGeolocationCNURL,
        downloadDetour: "proxy",
        updateInterval: "1d"
    )
}

private func ensureRemoteRuleSet(
    _ route: inout [String: Any],
    tag: String,
    url: String,
    downloadDetour: String,
    updateInterval: String
) {
    var ruleSets = (route["rule_set"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    if ruleSets.contains(where: { ($0["tag"] as? String) == tag }) {
        NSLog("MeshFlux ConfigModePatch v%@ rule_set already present: tag=%@ url=%@", configModePatchVersion, tag, url)
        return
    }
    ruleSets.append([
        "type": "remote",
        "tag": tag,
        "format": "binary",
        "url": url,
        "download_detour": downloadDetour,
        "update_interval": updateInterval
    ])
    route["rule_set"] = ruleSets
    NSLog("MeshFlux ConfigModePatch v%@ added rule_set: tag=%@ url=%@ detour=%@ interval=%@", configModePatchVersion, tag, url, downloadDetour, updateInterval)
}

private func removeRuleSet(_ route: inout [String: Any], tag: String) {
    guard var ruleSets = (route["rule_set"] as? [Any])?.compactMap({ $0 as? [String: Any] }), !ruleSets.isEmpty else {
        return
    }
    ruleSets.removeAll { ($0["tag"] as? String) == tag }
    route["rule_set"] = ruleSets
}
