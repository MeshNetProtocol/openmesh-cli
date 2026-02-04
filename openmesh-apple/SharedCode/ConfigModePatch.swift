//
//  ConfigModePatch.swift
//  SharedCode
//
//  Applies routing mode (rule vs global) to a sing-box config:
//  - Rule mode: only proxy-list domains → proxy + Google DNS; everything else → direct + local DNS. No geoip-cn in route rules.
//  - Global mode: geoip-cn → direct + local DNS; everything else → proxy + Google DNS.
//

import Foundation

/// Applies routing mode to a sing-box config JSON string. Returns patched JSON or original on parse/serialize error.
/// - Parameter content: Full sing-box config JSON string.
/// - Parameter isGlobalMode: true = global (geoip-cn direct, rest proxy); false = rule (only proxy-list proxy, rest direct).
public func applyRoutingModeToConfigContent(_ content: String, isGlobalMode: Bool) -> String {
    guard let data = content.data(using: .utf8),
          var config = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] else {
        return content
    }
    applyRoutingModeToConfig(&config, isGlobalMode: isGlobalMode)
    guard let out = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) else {
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
        // Global: route.rules = [sniff, geoip-cn → direct]. route.final = proxy.
        routeRules = buildGlobalModeRouteRules(from: routeRules)
        route["final"] = "proxy"
    } else {
        // Rule: route.rules = sniff + only rules with outbound "proxy". No geoip-cn. route.final = direct.
        routeRules = buildRuleModeRouteRules(from: routeRules)
        route["final"] = "direct"
    }

    route["rules"] = routeRules
    config["route"] = route

    // DNS by mode
    if var dns = config["dns"] as? [String: Any] {
        if isGlobalMode {
            dns["final"] = "google-dns"
            dns["rules"] = buildChinaLocalDNSRules()
        } else {
            dns["final"] = "local-dns"
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
    for rule in existing {
        if (rule["action"] as? String) == "sniff" {
            if !hasSniff {
                out.append(rule)
                hasSniff = true
            }
            continue
        }
        // drop all other rules; we only want sniff + geoip-cn
    }
    if !hasSniff {
        out.append(["action": "sniff"])
    }
    out.append(["rule_set": "geoip-cn", "outbound": "direct"])
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
        if rule["outbound"] as? String == "proxy" {
            out.append(rule)
        }
    }
    if !hasSniff {
        out.insert(["action": "sniff"], at: 0)
    }
    out.append(contentsOf: nonSniffNonRoute)
    return out
}

// MARK: - DNS rules

private func buildChinaLocalDNSRules() -> [[String: Any]] {
    [
        [
            "action": "route",
            "domain_suffix": [".cn"],
            "server": "local-dns",
            "strategy": "ipv4_only"
        ],
        [
            "action": "route",
            "domain_suffix": [".qq.com", ".weixinbridge.com"],
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
    var rules = buildChinaLocalDNSRules()
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
