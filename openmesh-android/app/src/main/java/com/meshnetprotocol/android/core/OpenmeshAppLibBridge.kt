package com.meshnetprotocol.android.core

import android.util.Log

/**
 * OpenMesh Go 库的 Kotlin 桥接实现
 * 封装 gomobile 生成的 Java 类（openmesh.AppLib），实现 OpenmeshAppLibProtocol 接口
 * 对应 iOS 的 OpenmeshAppLibBridge.swift
 */
class OpenmeshAppLibBridge(private val omLib: openmesh.AppLib) : OpenmeshAppLibProtocol {

    override fun initApp(config: ByteArray) {
        Log.d(TAG, "initApp called with config size: ${config.size}")
        omLib.initApp(config)
    }

    override fun generateMnemonic12(): String {
        return omLib.generateMnemonic12()
    }

    override fun createEvmWallet(mnemonic: String, password: String): String {
        return omLib.createEvmWallet(mnemonic, password)
    }

    override fun decryptEvmWallet(keystoreJSON: String, password: String): WalletSecretsV1 {
        val om = omLib.decryptEvmWallet(keystoreJSON, password)
        return WalletSecretsV1(
            v = om.v.toInt(),
            privateKeyHex = om.privateKeyHex,
            address = om.address
        )
    }

    override fun getTokenBalance(address: String, tokenName: String, networkName: String): String {
        val isMain = Thread.currentThread() == android.os.Looper.getMainLooper().thread
        val threadDesc = if (isMain) "main" else "background"
        Log.d(TAG, "getTokenBalance start thread=$threadDesc address=$address token=$tokenName network=$networkName")

        try {
            val balance = omLib.getTokenBalance(address, tokenName, networkName)
            Log.d(TAG, "getTokenBalance success thread=$threadDesc balance=$balance")
            return balance
        } catch (e: Exception) {
            Log.e(TAG, "getTokenBalance failed thread=$threadDesc error=${e.message}")
            throw e
        }
    }

    override fun getSupportedNetworks(): String {
        return omLib.getSupportedNetworks()
    }

    override fun getVpnStatus(): VpnStatus? {
        val om = omLib.vpnStatus ?: return null
        Log.d(TAG, "getVpnStatus connected=${om.connected} server=${om.server}")
        return VpnStatus(
            connected = om.connected,
            server = om.server,
            bytesIn = om.bytesIn,
            bytesOut = om.bytesOut
        )
    }

    companion object {
        private const val TAG = "OpenmeshAppLibBridge"
    }
}
