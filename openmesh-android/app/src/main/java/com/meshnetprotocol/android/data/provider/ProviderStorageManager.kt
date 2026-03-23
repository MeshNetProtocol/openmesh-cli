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
     * 获取完整配置快照文件路径
     */
    fun getFullConfigFile(providerId: String): File {
        return File(getProviderDirectory(providerId), "config_full.json")
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
            val configFile = getConfigFile(providerId)
            writeAtomicWithBackup(configFile, content)
            Log.i(TAG, "writeConfig: saved to ${configFile.absolutePath}")
            configFile
        }
    }

    /**
     * 写入完整配置快照（原子操作）
     */
    fun writeFullConfig(providerId: String, content: String): Result<File> {
        return runCatching {
            val configFile = getFullConfigFile(providerId)
            writeAtomicWithBackup(configFile, content)
            Log.i(TAG, "writeFullConfig: saved to ${configFile.absolutePath}")
            configFile
        }
    }
    
    /**
     * 写入路由规则（原子操作）
     */
    fun writeRoutingRules(providerId: String, content: String): Result<File> {
        return runCatching {
            val rulesFile = getRoutingRulesFile(providerId)
            writeAtomicWithBackup(rulesFile, content)
            Log.i(TAG, "writeRoutingRules: saved to ${rulesFile.absolutePath}")
            rulesFile
        }
    }

    private fun writeAtomicWithBackup(targetFile: File, content: String) {
        val providerDir = targetFile.parentFile ?: error("Missing provider directory for ${targetFile.absolutePath}")
        providerDir.mkdirs()

        if (targetFile.exists()) {
            val backupFile = File(providerDir, "${targetFile.name}.backup")
            targetFile.copyTo(backupFile, overwrite = true)
            Log.d(TAG, "writeAtomicWithBackup: backed up ${targetFile.absolutePath}")
        }

        val stagingFile = File(providerDir, "${targetFile.name}.staging")
        stagingFile.writeText(content, Charsets.UTF_8)

        // renameTo fails on some Android filesystems when target already exists
        if (targetFile.exists()) {
            targetFile.delete()
        }
        if (!stagingFile.renameTo(targetFile)) {
            // Fallback: copy staging content then delete staging file
            Log.w(TAG, "writeAtomicWithBackup: renameTo failed, using copy fallback")
            stagingFile.copyTo(targetFile, overwrite = true)
            stagingFile.delete()
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
    
    /**
     * 迁移已安装的 Provider：为没有 config_full.json 的 provider 创建一份。
     * 应在 Application/Activity 启动时调用一次。
     */
    fun migrateInstalledProviders() {
        listInstalledProviders().forEach { providerId ->
            val configFile = getConfigFile(providerId)
            val fullConfigFile = getFullConfigFile(providerId)
            if (configFile.exists() && !fullConfigFile.exists()) {
                try {
                    val content = configFile.readText(Charsets.UTF_8)
                    writeFullConfig(providerId, content)
                    Log.i(TAG, "migrateInstalledProviders: created config_full.json for $providerId")
                } catch (e: Exception) {
                    Log.w(TAG, "migrateInstalledProviders: failed for $providerId: ${e.message}")
                }
            }
        }
    }

    companion object {
        private const val TAG = "ProviderStorageManager"
    }
}
