package com.meshnetprotocol.android.vpn

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Align Android config handling with the runtime-safe profile shape used by iOS/Windows.
 *
 * The provider package may contain extra metadata and route/rule-set combinations that are
 * valid for distribution but brittle on Android runtime. This sanitizer keeps the provider
 * config sing-box-compatible and prefers a predictable "final -> proxy" routing model.
 */
object OpenMeshConfigSanitizer {
    private const val TAG = "OpenMeshConfigSanitizer"

    fun sanitize(configContent: String): String {
        return runCatching {
            val root = JSONObject(configContent)
            stripNonSingboxMetadata(root)
            normalizeOutboundsCompatibility(root)
            optimizeRemoteRuleSets(root)
            applyAndroidRoutePolicy(root)
            ensureProxyDomainCoverage(root)
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

    private fun normalizeOutboundsCompatibility(root: JSONObject) {
        val outbounds = root.optJSONArray("outbounds") ?: return
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.optJSONObject(i) ?: continue
            when (outbound.optString("type").lowercase()) {
                "selector", "urltest" -> outbound.remove("selected")
            }
        }
    }

    private fun optimizeRemoteRuleSets(root: JSONObject) {
        val route = root.optJSONObject("route") ?: return
        val ruleSets = route.optJSONArray("rule_set") ?: return
        for (i in 0 until ruleSets.length()) {
            val rs = ruleSets.optJSONObject(i) ?: continue
            if (rs.optString("type") != "remote") continue
            if (!rs.has("update_interval")) {
                rs.put("update_interval", "24h")
            }
            if (rs.has("download_interval")) {
                rs.remove("download_interval")
            }
        }
    }

    private fun applyAndroidRoutePolicy(root: JSONObject) {
        val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
        if (!route.has("final") || route.optString("final").isBlank()) {
            route.put("final", "proxy")
        }
        route.put("auto_detect_interface", true)

        val dns = root.optJSONObject("dns")
        if (dns != null) {
            if (!dns.has("final") || dns.optString("final").isBlank()) {
                dns.put("final", "google-dns")
            }
        }
    }

    private fun ensureProxyDomainCoverage(root: JSONObject) {
        val route = root.optJSONObject("route") ?: return
        val rules = route.optJSONArray("rules") ?: return

        val proxySuffixes = linkedSetOf(
            "x.com",
            "t.co",
            "twimg.com",
            "twttr.com",
            "tweetdeck.com",
        )
        val proxyDomains = linkedSetOf("x.com")

        var proxyDomainRule: JSONObject? = null
        var proxySuffixRule: JSONObject? = null

        for (i in 0 until rules.length()) {
            val rule = rules.optJSONObject(i) ?: continue
            if (rule.optString("outbound") != "proxy") continue
            if (proxyDomainRule == null && rule.has("domain")) {
                proxyDomainRule = rule
            }
            if (proxySuffixRule == null && rule.has("domain_suffix")) {
                proxySuffixRule = rule
            }
        }

        val domainRule = proxyDomainRule ?: JSONObject().put("outbound", "proxy").also { rules.put(it) }
        val suffixRule = proxySuffixRule ?: JSONObject().put("outbound", "proxy").also { rules.put(it) }

        mergeStringArray(domainRule, "domain", proxyDomains)
        mergeStringArray(suffixRule, "domain_suffix", proxySuffixes)
    }

    private fun mergeStringArray(target: JSONObject, key: String, additions: Set<String>) {
        val merged = linkedSetOf<String>()
        val current = target.optJSONArray(key)
        if (current != null) {
            for (i in 0 until current.length()) {
                val value = current.optString(i).trim()
                if (value.isNotEmpty()) {
                    merged.add(value)
                }
            }
        }
        merged.addAll(additions)
        target.put(key, JSONArray(merged.toList()))
    }
}
