package com.meshnetprotocol.android.vpn

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Injects provider-level routing_rules.json into route.rules at runtime.
 *
 * Android stores provider config and routing rules as separate files, same as Apple.
 * The Go runtime expects one merged sing-box config, so we mirror the shared merge logic here.
 */
object OpenMeshRoutingRuleInjector {
    private const val TAG = "OpenMeshRoutingRuleInjector"

    fun countInjectableRules(routingRulesContent: String?): Int {
        if (routingRulesContent.isNullOrBlank()) {
            return 0
        }

        return runCatching {
            parseRoutingRulesToSingBoxRules(routingRulesContent).size
        }.onFailure {
            Log.w(TAG, "countInjectableRules failed: ${it.message}")
        }.getOrDefault(0)
    }

    fun inject(configContent: String, routingRulesContent: String?): String {
        if (routingRulesContent.isNullOrBlank()) {
            return configContent
        }

        return runCatching {
            val root = JSONObject(configContent)
            val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
            val routeRules = route.optJSONArray("rules") ?: JSONArray().also { route.put("rules", it) }

            val sniffIndex = ensureSniffRule(routeRules)
            val injectedRules = parseRoutingRulesToSingBoxRules(routingRulesContent)
            if (injectedRules.isEmpty()) {
                Log.i(TAG, "inject: routing_rules.json present but produced 0 proxy rule(s)")
                return@runCatching configContent
            }

            val mergedRules = JSONArray()
            for (i in 0..sniffIndex) {
                mergedRules.put(routeRules.get(i))
            }
            for (rule in injectedRules) {
                mergedRules.put(rule)
            }
            for (i in (sniffIndex + 1) until routeRules.length()) {
                mergedRules.put(routeRules.get(i))
            }

            route.put("rules", mergedRules)
            root.toString().also {
                Log.i(TAG, "inject: merged ${injectedRules.size} routing rule(s) from provider routing_rules.json")
            }
        }.onFailure {
            Log.e(TAG, "inject failed: ${it.message}")
        }.getOrDefault(configContent)
    }

    private fun ensureSniffRule(routeRules: JSONArray): Int {
        for (i in 0 until routeRules.length()) {
            val rule = routeRules.optJSONObject(i) ?: continue
            if (rule.optString("action") == "sniff") {
                return i
            }
        }

        val newRules = JSONArray()
        newRules.put(JSONObject().put("action", "sniff"))
        for (i in 0 until routeRules.length()) {
            newRules.put(routeRules.get(i))
        }
        replaceArray(routeRules, newRules)
        return 0
    }

    private fun parseRoutingRulesToSingBoxRules(routingRulesContent: String): List<JSONObject> {
        val root = JSONObject(routingRulesContent)
        val proxyRules = root.optJSONObject("proxy")
        val source = proxyRules ?: root

        return if (source.has("rules")) {
            parseStructuredRules(source.optJSONArray("rules"))
        } else {
            parseSimpleRules(source)
        }
    }

    private fun parseStructuredRules(rulesArray: JSONArray?): List<JSONObject> {
        if (rulesArray == null) {
            return emptyList()
        }

        val aggregate = JSONObject()
        val keys = listOf("ip_cidr", "domain", "domain_suffix", "domain_regex")
        for (key in keys) {
            aggregate.put(key, JSONArray())
        }

        for (i in 0 until rulesArray.length()) {
            val rule = rulesArray.optJSONObject(i) ?: continue
            for (key in keys) {
                appendStrings(aggregate.getJSONArray(key), rule.optJSONArray(key))
            }
        }

        return parseSimpleRules(aggregate)
    }

    private fun parseSimpleRules(source: JSONObject): List<JSONObject> {
        val ipCidrs = uniqueStrings(source.optJSONArray("ip_cidr"))
        val domains = uniqueStrings(source.optJSONArray("domain"))
        val domainSuffixes = uniqueStrings(source.optJSONArray("domain_suffix"))
        val domainRegexes = uniqueStrings(source.optJSONArray("domain_regex"))

        val rules = mutableListOf<JSONObject>()
        if (ipCidrs.isNotEmpty()) {
            rules += JSONObject()
                .put("ip_cidr", JSONArray(ipCidrs))
                .put("outbound", "proxy")
        }
        if (domains.isNotEmpty()) {
            rules += JSONObject()
                .put("domain", JSONArray(domains))
                .put("outbound", "proxy")
        }
        if (domainSuffixes.isNotEmpty()) {
            val mainDomains = domainSuffixes.filterNot { it.startsWith(".") }
            if (mainDomains.isNotEmpty()) {
                rules += JSONObject()
                    .put("domain", JSONArray(mainDomains))
                    .put("outbound", "proxy")
            }

            val normalizedSuffixes = domainSuffixes.map { suffix ->
                if (suffix.startsWith(".")) suffix else ".$suffix"
            }
            rules += JSONObject()
                .put("domain_suffix", JSONArray(normalizedSuffixes))
                .put("outbound", "proxy")
        }
        if (domainRegexes.isNotEmpty()) {
            rules += JSONObject()
                .put("domain_regex", JSONArray(domainRegexes))
                .put("outbound", "proxy")
        }
        return rules
    }

    private fun uniqueStrings(array: JSONArray?): List<String> {
        if (array == null) {
            return emptyList()
        }

        val seen = LinkedHashSet<String>()
        for (i in 0 until array.length()) {
            val value = array.optString(i).trim()
            if (value.isNotEmpty()) {
                seen += value
            }
        }
        return seen.toList()
    }

    private fun appendStrings(target: JSONArray, values: JSONArray?) {
        if (values == null) {
            return
        }
        for (i in 0 until values.length()) {
            val value = values.optString(i).trim()
            if (value.isNotEmpty()) {
                target.put(value)
            }
        }
    }

    private fun replaceArray(target: JSONArray, source: JSONArray) {
        while (target.length() > 0) {
            target.remove(target.length() - 1)
        }
        for (i in 0 until source.length()) {
            target.put(source.get(i))
        }
    }
}
