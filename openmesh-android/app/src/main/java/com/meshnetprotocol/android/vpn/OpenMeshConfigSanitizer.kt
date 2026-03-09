package com.meshnetprotocol.android.vpn

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android-only runtime config sanitizer.
 *
 * Keep this layer small: platform adaptations belong here, provider/business routing does not.
 */
object OpenMeshConfigSanitizer {
    private const val TAG = "OpenMeshConfigSanitizer"

    fun sanitize(configContent: String): String {
        return runCatching {
            val root = JSONObject(configContent)

            ensureInboundTun(root)
            reorderAndInjectRouteRules(root)
            forceDebugOptions(root)
            injectFakeNodeForSingleNodeGroups(root)

            root.toString()
        }.onFailure {
            Log.e(TAG, "sanitize failed: ${it.message}")
        }.getOrDefault(configContent)
    }

    fun adaptTunAddressFamilies(configContent: String, enableIpv6: Boolean): String {
        return runCatching {
            if (enableIpv6) {
                return configContent
            }

            val root = JSONObject(configContent)
            val inbounds = root.optJSONArray("inbounds") ?: return configContent
            for (i in 0 until inbounds.length()) {
                val inbound = inbounds.optJSONObject(i) ?: continue
                if (!inbound.optString("type", "").equals("tun", ignoreCase = true)) {
                    continue
                }

                filterIpCidrs(inbound, "address", keepIpv6 = false)
                filterIpCidrs(inbound, "route_address", keepIpv6 = false)
                filterIpCidrs(inbound, "route_exclude_address", keepIpv6 = false)
                Log.i(TAG, "adaptTunAddressFamilies: removed IPv6 tun addresses for current Android network")
            }
            root.toString()
        }.onFailure {
            Log.e(TAG, "adaptTunAddressFamilies failed: ${it.message}")
        }.getOrDefault(configContent)
    }

    private fun ensureInboundTun(root: JSONObject) {
        val inbounds = root.optJSONArray("inbounds") ?: return
        for (i in 0 until inbounds.length()) {
            val inbound = inbounds.optJSONObject(i) ?: continue
            if (inbound.optString("type", "").equals("tun", ignoreCase = true)) {
                if (inbound.optInt("mtu", 0) <= 0) {
                    inbound.put("mtu", 1400)
                }
                if (!inbound.has("sniff")) {
                    inbound.put("sniff", true)
                }
                if (!inbound.has("sniff_override_destination")) {
                    inbound.put("sniff_override_destination", true)
                }

                Log.i(TAG, "ensureInboundTun: applied minimal Android defaults.")
            }
        }
    }

    /**
     * Reorders and injects essential route rules.
     * Align with iOS applyDynamicRoutingRulesToConfigContent:
     * 1. Ensure 'sniff' is Rule[0].
     * 2. Insert Block QUIC (UDP 443) immediately after sniff.
     * 3. Ensure DNS hijacking rules are also prioritized correctly.
     */
    private fun reorderAndInjectRouteRules(root: JSONObject) {
        val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
        val rules = route.optJSONArray("rules") ?: JSONArray().also { route.put("rules", it) }

        // 1. Separate special rules
        var sniffRule: JSONObject? = null
        val hijackDnsRules = mutableListOf<JSONObject>()
        val otherRules = mutableListOf<JSONObject>()

        for (i in 0 until rules.length()) {
            val rule = rules.optJSONObject(i) ?: continue
            val action = rule.optString("action")
            when {
                action == "sniff" -> {
                    if (sniffRule == null) sniffRule = rule
                }
                action == "hijack-dns" -> {
                    hijackDnsRules.add(rule)
                }
                // Check if it's our existing block-quic rule to avoid duplication
                (rule.optString("protocol") == "udp" && rule.optInt("port") == 443 && rule.optString("action") == "reject") -> {
                    // Skip, we will re-inject it at the right position
                }
                else -> {
                    otherRules.add(rule)
                }
            }
        }

        // 2. Build the new rules array
        val newRules = JSONArray()

        // Rule A: Sniff must be first
        newRules.put(sniffRule ?: JSONObject().apply { put("action", "sniff") })

        // Rule B: Block QUIC (UDP 443) must be very high priority (right after sniff)
        newRules.put(JSONObject().apply {
            put("protocol", "udp")
            put("port", 443)
            put("action", "reject")
        })

        // Rule C: Hijack DNS
        for (hr in hijackDnsRules) {
            newRules.put(hr)
        }

        // Rule D: Everything else
        for (or in otherRules) {
            newRules.put(or)
        }

        route.put("rules", newRules)
        Log.i(TAG, "reorderAndInjectRouteRules: Reorganized rules (Sniff -> Block QUIC -> DNS Hijack -> Others)")
    }

    private fun forceDebugOptions(root: JSONObject) {
        val log = root.optJSONObject("log") ?: JSONObject().also { root.put("log", it) }
        log.put("level", "debug")
        log.put("timestamp", true)
    }

    private fun injectFakeNodeForSingleNodeGroups(root: JSONObject) {
        val outbounds = root.optJSONArray("outbounds") ?: return
        for (i in 0 until outbounds.length()) {
            val out = outbounds.optJSONObject(i) ?: continue
            val type = out.optString("type").lowercase()
            if (type == "selector" || type == "urltest") {
                val members = out.optJSONArray("outbounds") ?: continue
                if (members.length() == 1) members.put("direct")
            }
        }
    }

    private fun filterIpCidrs(target: JSONObject, key: String, keepIpv6: Boolean) {
        val values = target.optJSONArray(key) ?: return
        val filtered = JSONArray()
        for (i in 0 until values.length()) {
            val value = values.optString(i).trim()
            if (value.isEmpty()) {
                continue
            }
            val isIpv6 = value.contains(':')
            if (isIpv6 == keepIpv6) {
                filtered.put(value)
            }
        }
        target.put(key, filtered)
    }
}
