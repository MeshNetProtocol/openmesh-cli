//
//  ProfileFromShared.swift
//  SharedCode
//
//  Converts shared/ two-file setup (routing_rules.json + singbox_base_config.json)
//  into a single sing-box compatible Profile config (one JSON string).
//  See docs/SHARED_TO_PROFILE.md for the relationship between shared files and Profile.
//

import Foundation

/// Builds a complete sing-box config string by merging:
/// - **Base config**: server/connection template (dns, inbounds, outbounds, route skeleton).
/// - **Routing rules**: from routing_rules.json (domain/domain_suffix/etc.) → inserted into route.rules.
/// - **Route final**: keep `route.final` from base profile.
///
/// Rule order in output: sniff → domain rules from routing_rules → hijack-dns.
/// - Parameter baseConfigJSON: Full sing-box template JSON string (e.g. from singbox_base_config.json or singbox_config.json).
/// - Parameter routingRulesJSON: Raw data of routing_rules.json (object with optional "domain", "domain_suffix", "ip_cidr", "domain_regex" arrays).
/// - Returns: One complete sing-box config JSON string (suitable for Profile file content or libbox).
public func buildMergedConfigFromShared(
    baseConfigJSON: String,
    routingRulesJSON: Data
) throws -> String {
    guard var config = try JSONSerialization.jsonObject(with: Data(baseConfigJSON.utf8), options: [.fragmentsAllowed]) as? [String: Any] else {
        throw ProfileFromSharedError.baseConfigNotObject
    }
    guard var route = config["route"] as? [String: Any] else {
        throw ProfileFromSharedError.baseConfigMissingRoute
    }

    var routeRules: [[String: Any]] = []
    if let existing = route["rules"] as? [Any] {
        for item in existing {
            if let dict = item as? [String: Any] {
                routeRules.append(dict)
            }
        }
    }

    if route["final"] == nil {
        route["final"] = "proxy"
    }

    let dynamicRules = try parseRoutingRulesToSingBoxRules(routingRulesJSON, outboundTag: "proxy")

    var sniffIndex = -1
    for (index, rule) in routeRules.enumerated() {
        if (rule["action"] as? String) == "sniff" {
            sniffIndex = index
            break
        }
    }
    if sniffIndex < 0 {
        routeRules.insert(["action": "sniff"], at: 0)
        sniffIndex = 0
    }
    routeRules.insert(contentsOf: dynamicRules, at: sniffIndex + 1)

    route["rules"] = routeRules
    config["route"] = route

    let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

/// Parses routing_rules.json-style data into sing-box route rule dictionaries.
/// Supports shape: { "domain": [], "domain_suffix": [], "ip_cidr": [], "domain_regex": [] }
/// or wrapped: { "proxy": { ... } } or { "rules": [ ... ] }.
private func parseRoutingRulesToSingBoxRules(_ data: Data, outboundTag: String) throws -> [[String: Any]] {
    let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    guard var dict = obj as? [String: Any] else {
        throw ProfileFromSharedError.routingRulesNotObject
    }
    if let proxy = dict["proxy"] as? [String: Any] {
        dict = proxy
    }
    if let rulesArray = dict["rules"] as? [[String: Any]] {
        return try parseSingBoxRuleObjectsToRules(rulesArray, outboundTag: outboundTag)
    }
    return try parseSimpleRoutingDictToRules(dict, outboundTag: outboundTag)
}

private func stringArray(_ value: Any?) -> [String] {
    guard let value else { return [] }
    if let arr = value as? [String] { return arr }
    if let arr = value as? [Any] {
        return arr.compactMap { $0 as? String }
    }
    if let s = value as? String { return [s] }
    return []
}

private func parseSimpleRoutingDictToRules(_ dict: [String: Any], outboundTag: String) throws -> [[String: Any]] {
    var rules: [[String: Any]] = []
    let ipCIDR = stringArray(dict["ip_cidr"])
    let domain = stringArray(dict["domain"])
    var domainSuffix = stringArray(dict["domain_suffix"])
    let domainRegex = stringArray(dict["domain_regex"])

    domainSuffix = Array(Set(domainSuffix)).sorted()

    if !ipCIDR.isEmpty { rules.append(["ip_cidr": ipCIDR, "outbound": outboundTag]) }
    if !domain.isEmpty { rules.append(["domain": domain, "outbound": outboundTag]) }
    if !domainSuffix.isEmpty {
        let mainDomains = domainSuffix.filter { !$0.hasPrefix(".") }
        if !mainDomains.isEmpty {
            rules.append(["domain": mainDomains, "outbound": outboundTag])
        }
        let normalizedSuffixes = domainSuffix.map { $0.hasPrefix(".") ? $0 : ".\($0)" }
        rules.append(["domain_suffix": normalizedSuffixes, "outbound": outboundTag])
    }
    if !domainRegex.isEmpty { rules.append(["domain_regex": domainRegex, "outbound": outboundTag]) }
    return rules
}

private func parseSingBoxRuleObjectsToRules(_ rulesArray: [[String: Any]], outboundTag: String) throws -> [[String: Any]] {
    var ipCIDR: [String] = []
    var domain: [String] = []
    var domainSuffix: [String] = []
    var domainRegex: [String] = []
    for rule in rulesArray {
        ipCIDR.append(contentsOf: stringArray(rule["ip_cidr"]))
        domain.append(contentsOf: stringArray(rule["domain"]))
        domainSuffix.append(contentsOf: stringArray(rule["domain_suffix"]))
        domainRegex.append(contentsOf: stringArray(rule["domain_regex"]))
    }
    let dict: [String: Any] = [
        "ip_cidr": ipCIDR,
        "domain": domain,
        "domain_suffix": domainSuffix,
        "domain_regex": domainRegex
    ]
    return try parseSimpleRoutingDictToRules(dict, outboundTag: outboundTag)
}

public enum ProfileFromSharedError: LocalizedError {
    case baseConfigNotObject
    case baseConfigMissingRoute
    case routingRulesNotObject

    public var errorDescription: String? {
        switch self {
        case .baseConfigNotObject: return "Base config is not a JSON object."
        case .baseConfigMissingRoute: return "Base config missing 'route' section."
        case .routingRulesNotObject: return "Routing rules is not a JSON object."
        }
    }
}
