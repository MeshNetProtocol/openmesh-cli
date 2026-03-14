package com.meshnetprotocol.android.vpn

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

object OpenMeshTunConfigResolver {
    fun resolve(configContent: String): OpenMeshTunOptions {
        val root = JSONObject(configContent)
        val inbounds = root.optJSONArray("inbounds")
            ?: throw IllegalStateException("Invalid profile: missing inbounds array")

        val tunInbound = findTunInbound(inbounds)
            ?: throw IllegalStateException("Invalid profile: no tun inbound found")

        val mtu = tunInbound.optInt("mtu", 1500).coerceIn(1280, 9000)
        val autoRoute = tunInbound.optBoolean("auto_route", true)

        val addresses = parseCidrs(tunInbound.optJSONArray("address"))
        if (addresses.isEmpty()) {
            throw IllegalStateException(
                "Invalid profile: tun inbound missing 'address' field. " +
                "Please update the provider configuration."
            )
        }

        val inet4Address = addresses.filter { !it.isIpv6 }
        val inet6Address = addresses.filter { it.isIpv6 }

        val dnsServer = pickDnsServer(root.optJSONObject("dns"), inet4Address, inet6Address)

        val routeAddress = parseCidrs(tunInbound.optJSONArray("route_address"))
        val routeExcludeAddress = parseCidrs(tunInbound.optJSONArray("route_exclude_address"))

        val includePackage = parseStringArray(tunInbound.optJSONArray("include_package"))
        val excludePackage = parseStringArray(tunInbound.optJSONArray("exclude_package"))

        return OpenMeshTunOptions(
            mtu = mtu,
            autoRoute = autoRoute,
            dnsServerAddress = dnsServer,
            inet4Address = inet4Address,
            inet6Address = inet6Address,
            inet4RouteAddress = routeAddress.filter { !it.isIpv6 },
            inet6RouteAddress = routeAddress.filter { it.isIpv6 },
            inet4RouteExcludeAddress = routeExcludeAddress.filter { !it.isIpv6 },
            inet6RouteExcludeAddress = routeExcludeAddress.filter { it.isIpv6 },
            includePackage = includePackage,
            excludePackage = excludePackage,
        )
    }

    private fun findTunInbound(inbounds: JSONArray): JSONObject? {
        for (i in 0 until inbounds.length()) {
            val inbound = inbounds.optJSONObject(i) ?: continue
            if (inbound.optString("type", "").equals("tun", ignoreCase = true)) {
                return inbound
            }
        }
        return null
    }

    private fun pickDnsServer(
        dns: JSONObject?,
        inet4Address: List<OpenMeshIpCidr>,
        inet6Address: List<OpenMeshIpCidr>,
    ): String {
        val servers = dns?.optJSONArray("servers")
        if (servers != null) {
            for (i in 0 until servers.length()) {
                val value = servers.opt(i)
                when (value) {
                    is String -> {
                        val server = value.trim()
                        if (server.isNotEmpty()) {
                            return server
                        }
                    }
                    is JSONObject -> {
                        val server = value.optString("address", "").trim()
                        if (server.isNotEmpty()) {
                            return server
                        }
                    }
                }
            }
        }

        return when {
            inet4Address.isNotEmpty() -> {
                Log.e("OpenMeshTunConfig", "CRITICAL: No IPv4 DNS server found in profile. VPN may not resolve domains.")
                ""
            }
            inet6Address.isNotEmpty() -> {
                Log.e("OpenMeshTunConfig", "CRITICAL: No IPv6 DNS server found in profile. VPN may not resolve domains.")
                ""
            }
            else -> {
                Log.e("OpenMeshTunConfig", "CRITICAL: No DNS configuration found. Domain resolution will likely fail.")
                ""
            }
        }
    }

    private fun parseCidrs(values: JSONArray?): List<OpenMeshIpCidr> {
        if (values == null) {
            return emptyList()
        }

        val result = ArrayList<OpenMeshIpCidr>(values.length())
        for (i in 0 until values.length()) {
            val raw = values.optString(i, "").trim()
            parseCidr(raw)?.let { result.add(it) }
        }
        return result
    }

    private fun parseStringArray(values: JSONArray?): List<String> {
        if (values == null) {
            return emptyList()
        }
        val out = ArrayList<String>(values.length())
        for (i in 0 until values.length()) {
            val raw = values.optString(i, "").trim()
            if (raw.isNotEmpty()) {
                out.add(raw)
            }
        }
        return out
    }

    private fun parseCidr(raw: String): OpenMeshIpCidr? {
        if (raw.isEmpty()) {
            return null
        }

        val parts = raw.split('/', limit = 2)
        if (parts.size != 2) {
            return null
        }

        val address = parts[0].trim()
        val prefix = parts[1].trim().toIntOrNull() ?: return null

        if (address.isEmpty()) {
            return null
        }

        val validPrefix = if (address.contains(':')) {
            prefix.coerceIn(0, 128)
        } else {
            prefix.coerceIn(0, 32)
        }

        return OpenMeshIpCidr(address = address, prefix = validPrefix)
    }
}
