package com.meshnetprotocol.android

import android.content.Context
import java.io.File

/**
 * 管理 Provider 文件的存储
 */
class ProviderFileManager(private val context: Context) {

    private val providersDir: File by lazy {
        File(context.filesDir, "providers")
    }

    /**
     * 获取 provider 目录
     */
    fun getProviderDirectory(providerID: String): File {
        return File(providersDir, providerID).apply {
            if (!exists()) mkdirs()
        }
    }

    /**
     * 获取 staging 目录（用于临时文件）
     */
    fun getStagingDirectory(): File {
        return File(providersDir, ".staging").apply {
            if (!exists()) mkdirs()
        }
    }

    /**
     * 获取 backup 目录
     */
    fun getBackupDirectory(): File {
        return File(providersDir, ".backup").apply {
            if (!exists()) mkdirs()
        }
    }

    /**
     * 创建临时的 staging 目录
     */
    fun createStagingDirectory(providerID: String): File {
        val stagingRoot = getStagingDirectory()
        val stagingDir = File(stagingRoot, "${providerID}-${System.currentTimeMillis()}")
        if (!stagingDir.exists()) {
            stagingDir.mkdirs()
        }
        return stagingDir
    }

    /**
     * 写入文件（原子操作）
     */
    fun writeFileAtomic(file: File, data: ByteArray) {
        val tempFile = File(file.parentFile, "${file.name}.tmp")
        try {
            tempFile.writeBytes(data)
            // 删除旧文件
            if (file.exists()) {
                file.delete()
            }
            // 重命名
            tempFile.renameTo(file)
        } catch (e: Exception) {
            tempFile.delete()
            throw e
        }
    }

    /**
     * 移动目录（用于 staging -> provider）
     */
    fun moveDirectory(from: File, to: File) {
        if (to.exists()) {
            // 移动到 backup
            val backupDir = getBackupDirectory()
            val backupTarget = File(backupDir, "${to.name}-${System.currentTimeMillis()}")
            to.copyRecursively(backupTarget)
            to.deleteRecursively()
        }
        from.copyRecursively(to)
        from.deleteRecursively()
    }

    /**
     * 删除 provider
     */
    fun deleteProvider(providerID: String) {
        val providerDir = getProviderDirectory(providerID)
        providerDir.deleteRecursively()
    }

    /**
     * 检查 provider 是否存在
     */
    fun providerExists(providerID: String): Boolean {
        return getProviderDirectory(providerID).exists()
    }

    /**
     * 获取 config.json 文件
     */
    fun getConfigFile(providerID: String): File {
        return File(getProviderDirectory(providerID), "config.json")
    }

    /**
     * 获取 routing_rules.json 文件
     */
    fun getRoutingRulesFile(providerID: String): File {
        return File(getProviderDirectory(providerID), "routing_rules.json")
    }
}
