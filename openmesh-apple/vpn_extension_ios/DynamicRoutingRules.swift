import Foundation
import Darwin

enum DynamicRoutingRulesError: LocalizedError {
    case invalidFormat(String)
    case invalidRuleType(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return message
        case .invalidRuleType(let type):
            return "Unknown rule type: \(type)"
        }
    }
}

struct DynamicRoutingRules: Equatable {
    var ipCIDR: [String] = []
    var domain: [String] = []
    var domainSuffix: [String] = []
    var domainRegex: [String] = []

    var isEmpty: Bool {
        ipCIDR.isEmpty && domain.isEmpty && domainSuffix.isEmpty && domainRegex.isEmpty
    }

    mutating func normalize() {
        ipCIDR = Self.uniquePreservingOrder(ipCIDR)
        domain = Self.uniquePreservingOrder(domain)
        domainSuffix = Self.uniquePreservingOrder(domainSuffix)
        domainRegex = Self.uniquePreservingOrder(domainRegex)
    }

    func toSingBoxRouteRules(outboundTag: String) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        if !ipCIDR.isEmpty { rules.append(["ip_cidr": ipCIDR, "outbound": outboundTag]) }
        if !domain.isEmpty { rules.append(["domain": domain, "outbound": outboundTag]) }
        if !domainSuffix.isEmpty { rules.append(["domain_suffix": domainSuffix, "outbound": outboundTag]) }
        if !domainRegex.isEmpty { rules.append(["domain_regex": domainRegex, "outbound": outboundTag]) }
        return rules
    }

    // MARK: - Loading

    static func load(from sharedDataDirURL: URL) throws -> (rules: DynamicRoutingRules, sourceURL: URL?) {
        let jsonURL = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
        let txtURL = sharedDataDirURL.appendingPathComponent("routing_rules.txt", isDirectory: false)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: jsonURL.path) {
            var rules = try parseJSON(Data(contentsOf: jsonURL))
            rules.normalize()
            return (rules, jsonURL)
        }
        if fileManager.fileExists(atPath: txtURL.path) {
            var rules = try parseText(String(decoding: Data(contentsOf: txtURL), as: UTF8.self))
            rules.normalize()
            return (rules, txtURL)
        }

        return (DynamicRoutingRules(), nil)
    }

    static func load(from sharedDataDirURL: URL, fallbackBundle: Bundle) throws -> (rules: DynamicRoutingRules, sourceURL: URL?) {
        let loaded = try load(from: sharedDataDirURL)
        if loaded.sourceURL != nil {
            return loaded
        }

        if let bundledURL = fallbackBundle.url(forResource: "routing_rules", withExtension: "json") {
            var rules = try parseJSON(Data(contentsOf: bundledURL))
            rules.normalize()
            return (rules, bundledURL)
        }

        return loaded
    }

    static func loadPreferNewest(from sharedDataDirURL: URL, fallbackBundle: Bundle) throws -> (rules: DynamicRoutingRules, sourceURL: URL?) {
        enum CandidateKind {
            case json
            case text
        }

        let fileManager = FileManager.default
        let groupJSON = sharedDataDirURL.appendingPathComponent("routing_rules.json", isDirectory: false)
        let groupTXT = sharedDataDirURL.appendingPathComponent("routing_rules.txt", isDirectory: false)
        let bundledJSON = fallbackBundle.url(forResource: "routing_rules", withExtension: "json")

        var candidates: [(url: URL, kind: CandidateKind, modifiedAt: Date)] = []
        candidates.reserveCapacity(3)

        func modificationDate(for url: URL) -> Date {
            (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        }

        if fileManager.fileExists(atPath: groupJSON.path) {
            candidates.append((groupJSON, .json, modificationDate(for: groupJSON)))
        }
        if fileManager.fileExists(atPath: groupTXT.path) {
            candidates.append((groupTXT, .text, modificationDate(for: groupTXT)))
        }
        if let bundledJSON {
            candidates.append((bundledJSON, .json, modificationDate(for: bundledJSON)))
        }

        guard let newest = candidates.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            return (DynamicRoutingRules(), nil)
        }

        var rules: DynamicRoutingRules
        switch newest.kind {
        case .json:
            rules = try parseJSON(Data(contentsOf: newest.url))
        case .text:
            rules = try parseText(String(decoding: Data(contentsOf: newest.url), as: UTF8.self))
        }
        rules.normalize()
        return (rules, newest.url)
    }

    // Accepts either:
    // 1) Simple shape: {"ip_cidr":[],"domain":[],"domain_suffix":[],"domain_regex":[]}
    // 2) Wrapped: {"proxy":{...simple shape...}}
    // 3) Advanced: {"rules":[{"ip_cidr":[...]}, {"domain_suffix":[...]}]}
    static func parseJSON(_ data: Data) throws -> DynamicRoutingRules {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard var dict = obj as? [String: Any] else {
            throw DynamicRoutingRulesError.invalidFormat("routing_rules.json must be a JSON object")
        }
        if let proxy = dict["proxy"] as? [String: Any] {
            dict = proxy
        }
        if let rulesArray = dict["rules"] as? [[String: Any]] {
            return try parseSingBoxRuleObjects(rulesArray)
        }
        return try parseSimpleJSONDict(dict)
    }

    private static func parseSimpleJSONDict(_ dict: [String: Any]) throws -> DynamicRoutingRules {
        var rules = DynamicRoutingRules()
        rules.ipCIDR = stringArray(dict["ip_cidr"])
        rules.domain = stringArray(dict["domain"])
        rules.domainSuffix = stringArray(dict["domain_suffix"])
        rules.domainRegex = stringArray(dict["domain_regex"])
        return rules
    }

    private static func parseSingBoxRuleObjects(_ rulesArray: [[String: Any]]) throws -> DynamicRoutingRules {
        var rules = DynamicRoutingRules()
        for rule in rulesArray {
            rules.ipCIDR.append(contentsOf: stringArray(rule["ip_cidr"]))
            rules.domain.append(contentsOf: stringArray(rule["domain"]))
            rules.domainSuffix.append(contentsOf: stringArray(rule["domain_suffix"]))
            rules.domainRegex.append(contentsOf: stringArray(rule["domain_regex"]))
        }
        return rules
    }

    static func parseText(_ text: String) throws -> DynamicRoutingRules {
        var rules = DynamicRoutingRules()
        var currentType: RuleType?

        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("//") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                currentType = try RuleType.parse(section)
                continue
            }

            if let (explicitType, value) = parseTypedLine(line) {
                apply(value: value, type: explicitType, to: &rules)
                continue
            }

            if let currentType {
                apply(value: line, type: currentType, to: &rules)
                continue
            }

            if isIPAddressOrCIDR(line) {
                apply(value: line, type: .ipCIDR, to: &rules)
            } else {
                apply(value: line, type: .domain, to: &rules)
            }
        }
        return rules
    }

    private static func parseTypedLine(_ line: String) -> (RuleType, String)? {
        if let idx = line.firstIndex(of: ":") {
            let type = String(line[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !type.isEmpty, !value.isEmpty else { return nil }
            if let parsed = try? RuleType.parse(type) {
                return (parsed, value)
            }
            return nil
        }
        let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 2 else { return nil }
        let type = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, !value.isEmpty else { return nil }
        if let parsed = try? RuleType.parse(type) {
            return (parsed, value)
        }
        return nil
    }

    private static func apply(value: String, type: RuleType, to rules: inout DynamicRoutingRules) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        switch type {
        case .ipCIDR:
            rules.ipCIDR.append(v)
        case .domain:
            rules.domain.append(v)
        case .domainSuffix:
            rules.domainSuffix.append(v)
        case .domainRegex:
            rules.domainRegex.append(v)
        }
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let arr = value as? [String] {
            return arr.filter { !$0.isEmpty }
        }
        if let s = value as? String, !s.isEmpty {
            return [s]
        }
        return []
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(values.count)
        for v in values {
            if seen.insert(v).inserted {
                out.append(v)
            }
        }
        return out
    }

    private static func isIPAddressOrCIDR(_ s: String) -> Bool {
        if s.contains("/") {
            let parts = s.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return false }
            return isValidIPAddress(String(parts[0]))
        }
        return isValidIPAddress(s)
    }

    private static func isValidIPAddress(_ s: String) -> Bool {
        var addr4 = in_addr()
        var addr6 = in6_addr()
        return s.withCString { cstr in
            inet_pton(AF_INET, cstr, &addr4) == 1 || inet_pton(AF_INET6, cstr, &addr6) == 1
        }
    }

    enum RuleType {
        case ipCIDR
        case domain
        case domainSuffix
        case domainRegex

        static func parse(_ raw: String) throws -> RuleType {
            switch raw.lowercased() {
            case "ip", "cidr", "ip_cidr", "ip-cidr":
                return .ipCIDR
            case "domain":
                return .domain
            case "suffix", "domain_suffix", "domain-suffix":
                return .domainSuffix
            case "regex", "domain_regex", "domain-regex":
                return .domainRegex
            default:
                throw DynamicRoutingRulesError.invalidRuleType(raw)
            }
        }
    }
}

