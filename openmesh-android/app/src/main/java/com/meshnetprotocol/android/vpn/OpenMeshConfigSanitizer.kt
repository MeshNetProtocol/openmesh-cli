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
            fixHijackDnsAfterSniff(root)
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

    private fun fixHijackDnsAfterSniff(root: JSONObject) {
        val route = root.optJSONObject("route") ?: return
        val rules = route.optJSONArray("rules") ?: return

        var sniffIdx = -1
        var hijackIdx = -1
        for (i in 0 until rules.length()) {
            val rule = rules.optJSONObject(i) ?: continue
            if (rule.optString("action") == "sniff") sniffIdx = i
            if (rule.optString("action") == "hijack-dns") hijackIdx = i
        }
        if (sniffIdx != -1 && hijackIdx != -1 && sniffIdx > hijackIdx) {
            val sniffRule = rules.remove(sniffIdx)
            val newRules = JSONArray().apply { put(sniffRule) }
            for (i in 0 until rules.length()) {
                newRules.put(rules.get(i))
            }
            route.put("rules", newRules)
            Log.i(TAG, "fixHijackDnsAfterSniff: moved sniff ahead of hijack-dns for Android tun DNS")
        }
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
