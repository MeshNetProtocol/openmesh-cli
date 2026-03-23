package com.meshnetprotocol.android.core

/**
 * VPN 状态数据结构
 * 对应 Go 代码中的 VpnStatus 结构体
 */
data class VpnStatus(
    val connected: Boolean,
    val server: String,
    val bytesIn: Long,
    val bytesOut: Long
)
