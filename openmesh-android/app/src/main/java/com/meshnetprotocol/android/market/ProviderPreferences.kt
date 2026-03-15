package com.meshnetprotocol.android.market

import android.content.Context
import android.util.Log
import com.meshnetprotocol.android.data.profile.ProfileRepository
import org.json.JSONObject

/**
 * Android 工程中供应商相关的 SharedPreferences 数据管理类。
 * 对齐 iOS 的供应商管理持久化逻辑。
 */
object ProviderPreferences {

    private const val TAG = "ProviderPreferences"
    private const val PREFS_NAME = "provider_market_prefs"

    // Keys
    private const val KEY_INSTALLED_PACKAGE_HASH = "installed_provider_package_hash"
    private const val KEY_PROVIDER_UPDATES_AVAILABLE = "provider_updates_available"
    private const val KEY_PROVIDER_UPDATES_LAST_CHECKED_AT = "provider_updates_last_checked_at"
    private const val KEY_INSTALLED_PROVIDER_ID_BY_PROFILE = "installed_provider_id_by_profile"
    private const val KEY_PROVIDER_NAMES = "provider_names"

    // ─── 安装的供应商 package_hash Map（providerID → packageHash）───
    // 对应 iOS: SharedPreferences.installedProviderPackageHash
    fun getInstalledPackageHashes(context: Context): Map<String, String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val jsonStr = prefs.getString(KEY_INSTALLED_PACKAGE_HASH, null) ?: return emptyMap()
        return try {
            val json = JSONObject(jsonStr)
            val result = mutableMapOf<String, String>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (json.has(key)) {
                    result[key] = json.getString(key)
                }
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse installed package hashes: ${e.message}")
            emptyMap()
        }
    }

    fun saveInstalledPackageHash(context: Context, providerID: String, hash: String) {
        try {
            val hashes = getInstalledPackageHashes(context).toMutableMap()
            hashes[providerID] = hash
            val json = JSONObject(hashes as Map<*, *>)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_INSTALLED_PACKAGE_HASH, json.toString())
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save installed package hash: ${e.message}")
        }
    }

    fun removeInstalledPackageHash(context: Context, providerID: String) {
        try {
            val hashes = getInstalledPackageHashes(context).toMutableMap()
            if (hashes.remove(providerID) != null) {
                val json = JSONObject(hashes as Map<*, *>)
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_INSTALLED_PACKAGE_HASH, json.toString())
                    .apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove installed package hash: ${e.message}")
        }
    }

    // ─── 可更新的供应商 Map（providerID → true/false）───
    // 对应 iOS: SharedPreferences.providerUpdatesAvailable
    fun getUpdatesAvailable(context: Context): Map<String, Boolean> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val jsonStr = prefs.getString(KEY_PROVIDER_UPDATES_AVAILABLE, null) ?: return emptyMap()
        return try {
            val json = JSONObject(jsonStr)
            val result = mutableMapOf<String, Boolean>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (json.has(key)) {
                    result[key] = json.getBoolean(key)
                }
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse updates available: ${e.message}")
            emptyMap()
        }
    }

    fun saveUpdatesAvailable(context: Context, updates: Map<String, Boolean>) {
        try {
            val json = JSONObject(updates as Map<*, *>)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_PROVIDER_UPDATES_AVAILABLE, json.toString())
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save updates available: ${e.message}")
        }
    }

    // ─── 上次检查更新的时间戳（秒）───
    // 对应 iOS: SharedPreferences.providerUpdatesLastCheckedAt
    fun getLastCheckedAt(context: Context): Long {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_PROVIDER_UPDATES_LAST_CHECKED_AT, 0L)
    }

    fun saveLastCheckedAt(context: Context, timestampSeconds: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_PROVIDER_UPDATES_LAST_CHECKED_AT, timestampSeconds)
            .apply()
    }

    // ─── 供应商 ID 到 Profile ID 的映射（providerID → profileID字符串）───
    // 对应 iOS: SharedPreferences.installedProviderIDByProfile（反向）
    fun getProviderByProfileID(context: Context): Map<String, String> {
        val prefs = context.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
        val jsonStr = prefs.getString(KEY_INSTALLED_PROVIDER_ID_BY_PROFILE, null) ?: return emptyMap()
        return try {
            val json = JSONObject(jsonStr)
            val result = mutableMapOf<String, String>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (json.has(key)) {
                    result[key] = json.getString(key)
                }
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse provider by profile ID: ${e.message}")
            emptyMap()
        }
    }

    fun saveProviderForProfile(context: Context, profileID: Long, providerID: String) {
        try {
            val mappings = getProviderByProfileID(context).toMutableMap()
            mappings[profileID.toString()] = providerID
            val json = JSONObject(mappings as Map<*, *>)
            context.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_INSTALLED_PROVIDER_ID_BY_PROFILE, json.toString())
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save provider for profile: ${e.message}")
        }
    }

    // ─── 工具函数：从 profileID 反查 providerID ───
    fun getProviderIDForProfile(context: Context, profileID: Long): String? {
        return getProviderByProfileID(context)[profileID.toString()]
    }

    // ─── 供应商 ID 到友好名称的映射（providerID → name）───
    fun getProviderNames(context: Context): Map<String, String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val jsonStr = prefs.getString(KEY_PROVIDER_NAMES, null) ?: return emptyMap()
        return try {
            val json = JSONObject(jsonStr)
            val result = mutableMapOf<String, String>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                result[key] = json.getString(key)
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse provider names: ${e.message}")
            emptyMap()
        }
    }

    fun saveProviderName(context: Context, providerID: String, name: String) {
        try {
            val names = getProviderNames(context).toMutableMap()
            names[providerID] = name
            val json = JSONObject(names as Map<*, *>)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_PROVIDER_NAMES, json.toString())
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save provider name: ${e.message}")
        }
    }

    fun getProviderName(context: Context, providerID: String): String {
        return getProviderNames(context)[providerID] ?: providerID
    }
}
