package com.meshnetprotocol.android.data.provider

import android.content.Context
import android.util.Log
import java.io.File

/**
 * Provider 配置文件存储管理器
 * 
 * 对齐 iOS/Windows的存储结构：
 * files/providers/{provider_id}/
 *   ├── config.json           # 主配置文件
 *   ├── routing_rules.json    # 路由规则（可选）
 *   └── rule-set/             # rule-set 目录（可选）
 */
class ProviderStorageManager(private val context: Context) {
    
    private val providersDir: File by lazy {
        File(context.filesDir, "providers").apply { mkdirs() }
    }
    
    /**
     * 获取供应商目录
     */
    fun getProviderDirectory(providerId: String): File {
        return File(providersDir, providerId).apply { mkdirs() }
    }
    
    /**
     * 获取配置文件路径
     */
    fun getConfigFile(providerId: String): File {
        return File(getProviderDirectory(providerId), "config.json")
    }
    
    /**
     * 获取路由规则文件路径
     */
    fun getRoutingRulesFile(providerId: String): File {
        return File(getProviderDirectory(providerId), "routing_rules.json")
    }
    
    /**
     * 获取 rule-set 目录
     */
    fun getRuleSetDirectory(providerId: String): File {
        return File(getProviderDirectory(providerId), "rule-set").apply { mkdirs() }
    }
    
    /**
     * 写入配置文件（原子操作，使用 staging/backup 机制）
     */
    fun writeConfig(providerId: String, content: String): Result<File> {
        return runCatching {
            val providerDir = getProviderDirectory(providerId)
            val configFile = File(providerDir, "config.json")
            
            // 备份旧文件
            if (configFile.exists()) {
                val backupFile = File(providerDir, "config.json.backup")
                configFile.copyTo(backupFile, overwrite = true)
                Log.d(TAG, "writeConfig: backed up ${configFile.absolutePath}")
            }
            
            // 写入临时文件
            val stagingFile = File(providerDir, "config.json.staging")
            stagingFile.writeText(content, Charsets.UTF_8)
            
            // 重命名为正式文件
            stagingFile.renameTo(configFile)
            
            // 清理备份（保留最近一次）
            // 可以在这里实现更复杂的版本管理
            
            Log.i(TAG, "writeConfig: saved to ${configFile.absolutePath}")
            configFile
        }
    }
    
    /**
     * 写入路由规则（原子操作）
     */
    fun writeRoutingRules(providerId: String, content: String): Result<File> {
        return runCatching {
            val providerDir = getProviderDirectory(providerId)
            val rulesFile = File(providerDir, "routing_rules.json")
            
            // 备份旧文件
            if (rulesFile.exists()) {
                val backupFile = File(providerDir, "routing_rules.json.backup")
                rulesFile.copyTo(backupFile, overwrite = true)
            }
            
            // 写入临时文件
            val stagingFile = File(providerDir, "routing_rules.json.staging")
            stagingFile.writeText(content, Charsets.UTF_8)
            
            // 重命名为正式文件
            stagingFile.renameTo(rulesFile)
            
            Log.i(TAG, "writeRoutingRules: saved to ${rulesFile.absolutePath}")
            rulesFile
        }
    }
    
    /**
     * 读取配置文件
     */
    fun readConfig(providerId: String): Result<String> {
        return runCatching {
            val configFile = getConfigFile(providerId)
            if (!configFile.exists()) {
                throw IllegalStateException("配置文件不存在：${configFile.absolutePath}")
            }
            configFile.readText(Charsets.UTF_8)
        }
    }
    
    /**
     * 读取路由规则
     */
    fun readRoutingRules(providerId: String): Result<String> {
        return runCatching {
            val rulesFile = getRoutingRulesFile(providerId)
            if (!rulesFile.exists()) {
                throw IllegalStateException("路由规则文件不存在：${rulesFile.absolutePath}")
            }
            rulesFile.readText(Charsets.UTF_8)
        }
    }
    
    /**
     * 检查配置文件是否存在
     */
    fun configExists(providerId: String): Boolean {
        return getConfigFile(providerId).exists()
    }
    
    /**
     * 删除供应商所有文件
     */
    fun deleteProvider(providerId: String): Boolean {
        return runCatching {
            val providerDir = getProviderDirectory(providerId)
            if (providerDir.exists()) {
                providerDir.deleteRecursively()
                Log.i(TAG, "deleteProvider: deleted $providerId")
                true
            } else {
                false
            }
        }.getOrDefault(false)
    }
    
    /**
     * 列出所有已安装的供应商 ID
     */
    fun listInstalledProviders(): List<String> {
        return providersDir.listFiles { file -> file.isDirectory && !file.name.startsWith(".") }
            ?.map { it.name }
            ?: emptyList()
    }
    
    companion object {
        private const val TAG = "ProviderStorageManager"
    }
}
