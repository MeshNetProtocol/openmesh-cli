package com.meshnetprotocol.android.core

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * PIN 码存储
 * 使用 Android EncryptedSharedPreferences 安全存储 PIN 码哈希
 * 对应 iOS 的 PINStore
 */
object PINStore {
    private const val PREFS_NAME = "pin_store_v1"
    private const val KEY_PIN_HASH = "pin_hash_v1"
    
    private val mutex = Mutex()
    
    /**
     * 检查是否已设置 PIN 码
     */
    fun hasPin(context: Context): Boolean {
        return try {
            val prefs = getEncryptedPrefs(context)
            prefs.contains(KEY_PIN_HASH)
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * 保存 PIN 码
     * @param pin 用户 PIN 码（6 位数字）
     */
    suspend fun savePin(context: Context, pin: String) = mutex.withLock {
        try {
            // 简单哈希处理（实际应该用更安全的哈希算法）
            val pinHash = pin.hashCode().toString()
            val prefs = getEncryptedPrefs(context)
            prefs.edit()
                .putString(KEY_PIN_HASH, pinHash)
                .apply()
        } catch (e: Exception) {
            throw Exception("保存 PIN 码失败：${e.message}")
        }
    }
    
    /**
     * 验证 PIN 码
     * @param pin 用户输入的 PIN 码
     * @return 如果 PIN 码正确返回 true，否则返回 false
     */
    suspend fun verifyPin(context: Context, pin: String): Boolean = mutex.withLock {
        try {
            val prefs = getEncryptedPrefs(context)
            val storedHash = prefs.getString(KEY_PIN_HASH, null)
            if (storedHash == null) return@withLock false
            val inputHash = pin.hashCode().toString()
            storedHash == inputHash
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * 清除 PIN 码
     */
    suspend fun clear(context: Context) = mutex.withLock {
        try {
            val prefs = getEncryptedPrefs(context)
            prefs.edit()
                .remove(KEY_PIN_HASH)
                .apply()
        } catch (e: Exception) {
            throw Exception("清除 PIN 码失败：${e.message}")
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
