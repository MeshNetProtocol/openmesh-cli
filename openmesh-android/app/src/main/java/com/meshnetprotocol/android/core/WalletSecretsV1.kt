package com.meshnetprotocol.android.core

/**
 * 钱包密钥数据结构 V1 版本
 * 对应 Go 代码中的 WalletSecretsV1 结构体
 */
data class WalletSecretsV1(
    val v: Int,
    val privateKeyHex: String,
    val address: String
)
