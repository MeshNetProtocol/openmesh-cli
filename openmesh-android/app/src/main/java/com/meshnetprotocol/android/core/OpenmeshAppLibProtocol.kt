package com.meshnetprotocol.android.core

/**
 * OpenMesh AppLib 协议接口
 * 定义所有从 Go 暴露出来的 API
 * 对应 iOS 的 OpenmeshAppLibProtocol
 */
interface OpenmeshAppLibProtocol {
    /**
     * 初始化应用库
     * @param config 配置数据（JSON 格式）
     */
    fun initApp(config: ByteArray)

    /**
     * 生成 12 个单词的助记词
     * @return 助记词字符串（空格分隔）
     */
    fun generateMnemonic12(): String

    /**
     * 创建 EVM 钱包
     * @param mnemonic 助记词
     * @param password 密码（用于加密 keystore）
     * @return 加密后的 keystore JSON 字符串
     */
    fun createEvmWallet(mnemonic: String, password: String): String

    /**
     * 解密 EVM 钱包
     * @param keystoreJSON 加密的 keystore JSON
     * @param password 密码
     * @return 解密后的钱包密钥信息
     */
    fun decryptEvmWallet(keystoreJSON: String, password: String): WalletSecretsV1

    /**
     * 获取代币余额
     * @param address 钱包地址
     * @param tokenName 代币名称（如 USDC）
     * @param networkName 网络名称（如 base-mainnet）
     * @return 余额字符串（格式化后，如 "123.456789"）
     */
    fun getTokenBalance(address: String, tokenName: String, networkName: String): String

    /**
     * 获取支持的网络列表
     * @return JSON 数组字符串，如 ["base-mainnet", "base-testnet"]
     */
    fun getSupportedNetworks(): String

    /**
     * 获取 VPN 状态
     * @return VPN 状态对象，如果尚未初始化则返回 null
     */
    fun getVpnStatus(): VpnStatus?
}
