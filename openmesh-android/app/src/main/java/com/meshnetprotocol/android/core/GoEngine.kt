package com.meshnetprotocol.android.core

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Go 引擎错误类型
 */
sealed class GoEngineError(message: String) : Exception(message) {
    object NewLibReturnedNil : GoEngineError("无法加载核心库，请重新安装应用或联系支持。")
    object NotInitialized : GoEngineError("Go 引擎尚未初始化")
}

/**
 * Go 引擎单例
 * 管理 OpenMesh Go 库的生命周期和初始化
 * 对应 iOS 的 GoEngine.shared
 * 
 * 注意：这是一个简化版本，专注于实际使用场景
 */
class GoEngine private constructor(private val context: Context) {
    
    companion object {
        @Volatile
        private var instance: GoEngine? = null
        
        /**
         * 初始化 Go 引擎单例
         * 必须在 Application onCreate 中调用
         */
        fun initialize(context: Context): GoEngine {
            return instance ?: synchronized(this) {
                val newInstance = GoEngine(context.applicationContext)
                instance = newInstance
                newInstance
            }
        }
        
        /**
         * 获取 Go 引擎实例
         * 必须先调用 initialize()
         */
        fun shared(): GoEngine {
            return instance ?: throw IllegalStateException(
                "GoEngine not initialized. Call GoEngine.initialize() in Application.onCreate()"
            )
        }

        /**
         * 同步初始化 libbox 环境（专为 VPN 服务启动设计）
         */
        fun setupLibboxSync(context: Context) {
            val baseDir = context.filesDir
            val workingDir = context.getExternalFilesDir(null) ?: baseDir
            val tempDir = context.cacheDir
            try {
                val setupOptions = libbox.SetupOptions()
                setupOptions.basePath = baseDir.path
                setupOptions.workingPath = workingDir.path
                setupOptions.tempPath = tempDir.path
                setupOptions.fixAndroidStack = true
                // 使用端口 0 让系统自动分配可用端口，避免静态端口冲突
                setupOptions.commandServerListenPort = 0
                setupOptions.commandServerSecret = "OpenMesh-Secret-2026"
                libbox.Libbox.setup(setupOptions)
                
                // 对齐 iOS: 重定向 stderr 到文件以便排查 Go 层崩溃
                val stderrLogPath = java.io.File(context.cacheDir, "stderr.log").absolutePath
                try {
                    libbox.Libbox.redirectStderr(stderrLogPath)
                } catch (e: Exception) {
                    Log.w("GoEngine", "Failed to redirect stderr: ${e.message}")
                }

                // 对齐 iOS: 设置内存限制保护 (256MB)
                try {
                    libbox.Libbox.setMemoryLimit(true)
                } catch (e: Exception) {
                    Log.w("GoEngine", "Failed to set memory limit: ${e.message}")
                }

                Log.i("GoEngine", "libbox setup completed (sync). stderr.log: $stderrLogPath")
            } catch (e: Exception) {
                Log.e("GoEngine", "libbox setup failed (sync): ${e.message}")
            }
        }
    }
    
    private val TAG = "GoEngine"
    private val initialized = AtomicBoolean(false)
    
    @Volatile
    private var omLib: openmesh.AppLib? = null
    
    @Volatile
    private var appLib: OpenmeshAppLibProtocol? = null
    
    private var cachedConfig: ByteArray = ByteArray(0)
    
    /**
     * 懒初始化：第一次使用时才创建
     */
    init {
        Log.d(TAG, "GoEngine instance created with context: ${context.applicationContext?.javaClass?.simpleName}")
    }
    
    /**
     * 生成 12 个单词的助记词
     */
    suspend fun generateMnemonic12(): String = withContext(Dispatchers.IO) {
        ensureReady()
        appLib?.generateMnemonic12() ?: throw GoEngineError.NotInitialized
    }
    
    /**
     * 创建 EVM 钱包
     * @param mnemonic 助记词
     * @param pin PIN 码（用于加密 keystore）
     * @return 加密后的 keystore JSON 字符串
     */
    suspend fun createEvmWallet(mnemonic: String, pin: String): String = withContext(Dispatchers.IO) {
        ensureReady()
        appLib?.createEvmWallet(mnemonic, pin) ?: throw GoEngineError.NotInitialized
    }
    
    /**
     * 解密 EVM 钱包
     * @param keystoreJSON 加密的 keystore JSON
     * @param pin PIN 码
     * @return 解密后的钱包密钥信息
     */
    suspend fun decryptEvmWallet(keystoreJSON: String, pin: String): WalletSecretsV1 = withContext(Dispatchers.IO) {
        ensureReady()
        appLib?.decryptEvmWallet(keystoreJSON, pin) ?: throw GoEngineError.NotInitialized
    }
    
    /**
     * 获取代币余额
     */
    suspend fun getTokenBalance(address: String, tokenName: String, networkName: String): String = withContext(Dispatchers.IO) {
        val requestId = java.util.UUID.randomUUID().toString().take(8)
        val maskedAddr = maskAddress(address)
        Log.d(TAG, "getTokenBalance start request_id=$requestId address=$maskedAddr token=$tokenName network=$networkName")
        
        try {
            ensureReady()
            val balance = appLib?.getTokenBalance(address, tokenName, networkName) 
                ?: throw GoEngineError.NotInitialized
            Log.d(TAG, "getTokenBalance success request_id=$requestId balance=$balance")
            balance
        } catch (e: Exception) {
            Log.e(TAG, "getTokenBalance failed request_id=$requestId error=${e.message}")
            throw e
        }
    }
    
    /**
     * 获取支持的网络列表
     */
    suspend fun getSupportedNetworks(): List<String> = withContext(Dispatchers.IO) {
        ensureReady()
        val networksJson = appLib?.getSupportedNetworks() ?: throw GoEngineError.NotInitialized
        
        // 解析 JSON 数组
        try {
            org.json.JSONArray(networksJson).run {
                List(length()) { i -> getString(i) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse networks JSON: $networksJson", e)
            throw e
        }
    }
    
    /**
     * 初始化或重新配置 Go 库
     * @param config 配置数据（JSON 格式）
     */
    suspend fun reconfigure(config: ByteArray) = withContext(Dispatchers.IO) {
        cachedConfig = config.copyOf()
        initializeLib(config)
    }
    
    /**
     * 重置 Go 引擎状态
     */
    suspend fun reset() = withContext(Dispatchers.IO) {
        omLib = null
        appLib = null
        cachedConfig = ByteArray(0)
        initialized.set(false)
        Log.d(TAG, "GoEngine reset completed")
    }
    
    /**
     * 释放运行时资源以响应内存压力
     * 用于 Android 退到后台后的内存回收
     */
    suspend fun releaseRuntimeForMemoryPressure() = withContext(Dispatchers.IO) {
        Log.d(TAG, "releaseRuntimeForMemoryPressure begin")
        omLib = null
        appLib = null
        Log.d(TAG, "releaseRuntimeForMemoryPressure end")
    }
    
    /**
     * 获取 VPN 状态
     */
    suspend fun getVpnStatus(): VpnStatus? = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "getVpnStatus start")
            ensureReady()
            val status = appLib?.getVpnStatus()
            if (status != null) {
                Log.d(TAG, "getVpnStatus success connected=${status.connected} server=${status.server}")
            } else {
                Log.d(TAG, "getVpnStatus success nil")
            }
            status
        } catch (e: Exception) {
            Log.e(TAG, "getVpnStatus failed error=${e.message}")
            null
        }
    }
    
    // MARK: - Private methods
    
    /**
     * 确保 Go 库已就绪
     */
    private suspend fun ensureReady() {
        if (!initialized.get()) {
            initializeLib(cachedConfig)
        }
    }
    
    /**
     * 初始化 Go 库
     */
    private suspend fun initializeLib(config: ByteArray) = withContext(Dispatchers.IO) {
        try {
            if (omLib == null) {
                // 设置 gomobile 上下文
                go.Seq.setContext(context)
                
                // 初始化 libbox 环境
                val baseDir = context.filesDir
                val workingDir = context.getExternalFilesDir(null) ?: baseDir
                val tempDir = context.cacheDir
                try {
                    setupLibboxSync(context)
                } catch (e: Exception) {
                    Log.e(TAG, "libbox setup failed: ${e.message}")
                }

                // 使用 AAR 中 gomobile 生成的真实工厂方法
                val goLib = openmesh.Openmesh.newLib()
                    ?: throw GoEngineError.NewLibReturnedNil
                
                omLib = goLib
                appLib = OpenmeshAppLibBridge(goLib)
                Log.d(TAG, "OpenMeshGo library initialized")
            }
            
            if (config.isNotEmpty()) {
                appLib?.initApp(config)
            }
            
            initialized.set(true)
            Log.d(TAG, "GoEngine initialization completed")
        } catch (e: Exception) {
            Log.e(TAG, "GoEngine initialization failed: ${e.message}", e)
            throw e
        }
    }
    
    /**
     * 掩码钱包地址用于日志输出
     */
    private fun maskAddress(address: String): String {
        val trimmed = address.trim()
        if (trimmed.length <= 12) return trimmed
        return "${trimmed.take(6)}...${trimmed.takeLast(4)}"
    }
}
