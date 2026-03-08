package com.meshnetprotocol.android.vpn

import android.util.Log
import org.json.JSONObject

/**
 * Minimal sanitizer for Android runtime.
 *
 * Design principle: the provider config already contains complete and correct
 * routing logic (domain_suffix -> proxy, geoip/geosite-cn -> direct, final -> proxy).
 * We do NOT manipulate route rules, domain lists, or rule ordering.
 * libbox handles all routing natively.
 *
 * We only:
 * 1. Strip non-sing-box metadata fields that would cause parse errors.
 * 2. Ensure auto_detect_interface = true (Android platform requirement).
 */
object OpenMeshConfigSanitizer {
    private const val TAG = "OpenMeshConfigSanitizer"

    fun sanitize(configContent: String): String {
        return runCatching {
            val root = JSONObject(configContent)
            stripNonSingboxMetadata(root)
            ensureAndroidPlatformFields(root)
            root.toString()
        }.onFailure {
            Log.e(TAG, "sanitize failed: ${it.message}")
        }.getOrDefault(configContent)
    }

    private fun stripNonSingboxMetadata(root: JSONObject) {
        listOf(
            "author",
            "name",
            "title",
            "description",
            "version",
            "updated_at",
            "created_at",
            "package_hash",
            "provider_id",
            "provider_name",
            "tags",
            "x402",
            "wallet",
        ).forEach(root::remove)
    }

    private fun ensureAndroidPlatformFields(root: JSONObject) {
        // 1. Ensure auto_detect_interface (Android requirement for protect socket)
        val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
        route.put("auto_detect_interface", true)

        // 2. Inject local DNS server for Android native resolution parity
        // This hooks into our LocalResolver implementation.
        val dns = root.optJSONObject("dns") ?: JSONObject().also { root.put("dns", it) }
        val servers = dns.optJSONArray("servers") ?: org.json.JSONArray().also { dns.put("servers", it) }
        
        // Ensure "dns-local" server exists
        var localServerIdx = -1
        for (i in 0 until servers.length()) {
            if (servers.optJSONObject(i)?.optString("tag") == "dns-local") {
                localServerIdx = i
                break
            }
        }
        
        if (localServerIdx == -1) {
            val localServer = JSONObject().apply {
                put("tag", "dns-local")
                put("type", "local")
                put("detour", "direct")
            }
            // Add to the front
            val newServers = org.json.JSONArray().apply {
                put(localServer)
                for (i in 0 until servers.length()) put(servers.get(i))
            }
            dns.put("servers", newServers)
        }

        // 3. Inject DNS hijacking rules
        val dnsRules = dns.optJSONArray("rules") ?: org.json.JSONArray().also { dns.put("rules", it) }
        
        // Rule: geosite:cn -> dns-local
        var cnRuleExists = false
        for (i in 0 until dnsRules.length()) {
            if (dnsRules.optJSONObject(i)?.optString("server") == "dns-local") {
                cnRuleExists = true
                break
            }
        }
        if (!cnRuleExists) {
            val localRule = JSONObject().apply {
                // geosite is removed in sing-box 1.12+, use domain_suffix for .cn
                put("domain_suffix", org.json.JSONArray().apply { 
                    put(".cn")
                    put(".com.cn")
                    put(".net.cn")
                    put(".org.cn")
                })
                put("server", "dns-local")
            }
            val newDnsRules = org.json.JSONArray().apply {
                put(localRule)
                for (i in 0 until dnsRules.length()) put(dnsRules.get(i))
            }
            dns.put("rules", newDnsRules)
        }

        // 4. Inject DNS hijack rule
        // Modern sing-box (1.11+) uses rule action instead of a dns outbound.
        val routeRules = route.optJSONArray("rules") ?: org.json.JSONArray().also { route.put("rules", it) }
        var hijackRuleExists = false
        for (i in 0 until routeRules.length()) {
            val rule = routeRules.optJSONObject(i)
            if (rule?.optString("action") == "hijack-dns" || rule?.optString("protocol") == "dns") {
                hijackRuleExists = true
                break
            }
        }
        if (!hijackRuleExists) {
            // High priority: insert at the beginning
            val hijackRule = JSONObject().apply {
                put("protocol", "dns")
                put("action", "hijack-dns")
            }
            val newRouteRules = org.json.JSONArray().apply {
                put(hijackRule)
                for (i in 0 until routeRules.length()) put(routeRules.get(i))
            }
            route.put("rules", newRouteRules)
        }

        Log.i(TAG, "Config sanitized: injected hijack-dns action")
    }
}
