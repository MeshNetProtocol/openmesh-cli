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

    fun validateAndLog(configContent: String): String {
        runCatching {
            val root = JSONObject(configContent)
            logDebugOptions(root)
        }.onFailure {
            Log.e(TAG, "validateAndLog failed: ${it.message}")
        }
        return configContent
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

    private fun logDebugOptions(root: JSONObject) {
        val log = root.optJSONObject("log") ?: return
        val currentLevel = log.optString("level", "not set")
        Log.i(TAG, "logDebugOptions: Keeping profile log level: $currentLevel")
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
