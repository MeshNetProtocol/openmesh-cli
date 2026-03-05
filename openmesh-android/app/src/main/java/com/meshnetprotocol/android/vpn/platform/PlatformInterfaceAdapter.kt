package com.meshnetprotocol.android.vpn.platform

class PlatformInterfaceAdapter {
    fun includeAllNetworks(): Boolean = true

    fun excludeLocalNetworks(): Boolean = false

    fun underVpnService(): Boolean = true
}
