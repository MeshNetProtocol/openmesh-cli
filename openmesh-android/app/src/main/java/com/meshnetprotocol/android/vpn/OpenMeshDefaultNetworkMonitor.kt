package com.meshnetprotocol.android.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import java.net.Inet6Address

object OpenMeshDefaultNetworkMonitor {
    private const val TAG = "OpenMeshDefaultNetwork"

    @Volatile
    private var defaultNetwork: Network? = null

    fun update(network: Network?) {
        defaultNetwork = network
    }

    fun clear() {
        defaultNetwork = null
    }

    fun currentOrSelect(context: Context?): Network? {
        val cm = context?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return null
        val current = defaultNetwork
        if (isUsableUnderlyingNetwork(cm, current)) {
            return current
        }
        return selectUnderlyingNetwork(cm)?.also { defaultNetwork = it }
    }

    fun selectUnderlyingNetwork(cm: ConnectivityManager): Network? {
        val activeNetwork = cm.activeNetwork
        if (isUsableUnderlyingNetwork(cm, activeNetwork)) {
            return activeNetwork
        }

        val candidates = cm.allNetworks.filter { isUsableUnderlyingNetwork(cm, it) }
        return candidates.maxByOrNull { network ->
            val caps = cm.getNetworkCapabilities(network)
            var score = 0
            if (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true) score += 4
            if (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == true) score += 2
            if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) score += 1
            score
        }
    }

    fun isUsableUnderlyingNetwork(cm: ConnectivityManager, network: Network?): Boolean {
        if (network == null) {
            return false
        }
        val caps = cm.getNetworkCapabilities(network) ?: return false
        val linkProps = cm.getLinkProperties(network) ?: return false
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            return false
        }
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            return false
        }
        val interfaceName = linkProps.interfaceName ?: return false
        if (interfaceName == "tun0" || interfaceName.startsWith("tun")) {
            return false
        }
        return true
    }

    fun interfaceName(cm: ConnectivityManager, network: Network?): String? {
        if (network == null) {
            return null
        }
        return cm.getLinkProperties(network)?.interfaceName
    }

    fun hasUsableIpv6(cm: ConnectivityManager, network: Network?): Boolean {
        if (!isUsableUnderlyingNetwork(cm, network)) {
            return false
        }
        val linkProps = cm.getLinkProperties(network) ?: return false
        val hasGlobalIpv6Address = linkProps.linkAddresses.any { linkAddress ->
            val address = linkAddress.address
            address is Inet6Address &&
                !address.isLinkLocalAddress &&
                !address.isLoopbackAddress &&
                !address.isMulticastAddress &&
                !address.isSiteLocalAddress
        }
        val hasIpv6DefaultRoute = linkProps.routes.any { route ->
            route.isDefaultRoute && route.destination?.address is Inet6Address
        }
        if (!hasGlobalIpv6Address || !hasIpv6DefaultRoute) {
            Log.i(
                TAG,
                "IPv6 unavailable on ${linkProps.interfaceName}: globalAddress=$hasGlobalIpv6Address defaultRoute=$hasIpv6DefaultRoute"
            )
        }
        return hasGlobalIpv6Address && hasIpv6DefaultRoute
    }
}
