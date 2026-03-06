package com.meshnetprotocol.android.core

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 钱包存储错误类型
 */
class WalletStoreError(message: String) : Exception(message)

/**
 * 钱包数据存储
 * 使用 Android EncryptedSharedPreferences 安全存储钱包数据
 * 对应 iOS 的 WalletStore（Keychain）
 */
object WalletStore {
    private const val PREFS_NAME = "wallet_blob_v1"
    private const val KEY_WALLET_BLOB = "wallet_json"
    
    private val mutex = Mutex()
    
    /**
     * 检查是否有钱包
     */
    fun hasWallet(context: Context): Boolean {
        return try {
            val prefs = getEncryptedPrefs(context)
            prefs.contains(KEY_WALLET_BLOB)
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * 保存钱包 JSON 数据
     * @param blob Go 返回的钱包 JSON bytes（UTF-8 编码）
     */
    suspend fun saveWalletBlob(context: Context, blob: ByteArray) = mutex.withLock {
        try {
            val prefs = getEncryptedPrefs(context)
            prefs.edit()
                .putString(KEY_WALLET_BLOB, String(blob, Charsets.UTF_8))
                .apply()
        } catch (e: Exception) {
            throw Exception("保存钱包失败：${e.message}")
        }
    }
    
    /**
     * 加载钱包 JSON 数据
     * @return 钱包 JSON bytes，如果不存在则返回 null
     */
    suspend fun loadWalletBlob(context: Context): ByteArray? = mutex.withLock {
        try {
            val prefs = getEncryptedPrefs(context)
            prefs.getString(KEY_WALLET_BLOB, null)?.toByteArray(Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * 清除钱包数据
     */
    suspend fun clear(context: Context) = mutex.withLock {
        try {
            val prefs = getEncryptedPrefs(context)
            prefs.edit()
                .remove(KEY_WALLET_BLOB)
                .apply()
        } catch (e: Exception) {
            throw Exception("清除钱包失败：${e.message}")
        }
    }
    
    /**
     * 获取加密的 SharedPreferences 实例
     */
    private fun getEncryptedPrefs(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        
        return EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }
}
