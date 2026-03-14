package com.meshnetprotocol.android.vpn

data class OpenMeshIpCidr(
    val address: String,
    val prefix: Int,
) {
    val isIpv6: Boolean get() = address.contains(':')
}

data class OpenMeshTunOptions(
    val mtu: Int,
    val autoRoute: Boolean,
    val dnsServerAddress: String,
    val inet4Address: List<OpenMeshIpCidr>,
    val inet6Address: List<OpenMeshIpCidr>,
    val inet4RouteAddress: List<OpenMeshIpCidr>,
    val inet6RouteAddress: List<OpenMeshIpCidr>,
    val inet4RouteExcludeAddress: List<OpenMeshIpCidr>,
    val inet6RouteExcludeAddress: List<OpenMeshIpCidr>,
    val includePackage: List<String>,
    val excludePackage: List<String>,
)
