package com.meshnetprotocol.android.market

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 供应商更新检查后端。
 * 对应 iOS 的 MarketService.checkInstalledProvidersUpdate()。
 */
object UpdateChecker {
    private const val TAG = "UpdateChecker"
    private const val BASE_URL = "https://openmesh-api.ribencong.workers.dev/api/v1"
    private const val RATE_LIMIT_SECONDS = 3600L  // 1小时

    // 广播 Action，更新状态变化时发送
    const val ACTION_UPDATE_STATE_CHANGED = "com.meshnetprotocol.android.market.UPDATE_STATE_CHANGED"

    /**
     * 检查已安装供应商的更新。
     * 对应 iOS: checkInstalledProvidersUpdate()
     *
     * 调用方式：在 IO 线程调用，函数内部会切回主线程发广播。
     */
    suspend fun checkInstalledProvidersUpdate(context: Context) {
        // Step 1: 读取已安装的供应商 hash 列表
        val installedHashes = ProviderPreferences.getInstalledPackageHashes(context)
        if (installedHashes.isEmpty()) {
            Log.i(TAG, "checkInstalledProvidersUpdate: skip (no installed providers)")
            return
        }

        // Step 2: 检查限流（1小时内不重复检查）
        val now = System.currentTimeMillis() / 1000L
        val lastCheckedAt = ProviderPreferences.getLastCheckedAt(context)
        if (now - lastCheckedAt < RATE_LIMIT_SECONDS) {
            Log.i(TAG, "checkInstalledProvidersUpdate: skip (rate limited). elapsed=${now - lastCheckedAt}s")
            return
        }
        ProviderPreferences.saveLastCheckedAt(context, now)
        Log.i(TAG, "checkInstalledProvidersUpdate: start checking ${installedHashes.size} providers")

        // Step 3: 逐个查询供应商最新 hash（串行，避免并发网络压力）
        val updatesFound = mutableMapOf<String, Boolean>()
        val checkedIDs = mutableSetOf<String>()

        for ((providerID, localHash) in installedHashes) {
            // 跳过本地导入的供应商（没有服务器记录）
            if (providerID.startsWith("imported-")) continue

            checkedIDs.add(providerID)
            try {
                val latestHash = fetchLatestPackageHash(providerID)
                if (latestHash != null && latestHash.isNotEmpty() && latestHash != localHash) {
                    Log.i(TAG, "Update found for $providerID (local=$localHash, remote=$latestHash)")
                    updatesFound[providerID] = true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to check update for $providerID: ${e.message}")
            }
        }

        // Step 4: 更新本地存储（对齐 iOS 的 merge 逻辑）
        val existingUpdates = ProviderPreferences.getUpdatesAvailable(context).toMutableMap()
        var changed = false
        for (providerID in checkedIDs) {
            val newValue = updatesFound[providerID] == true
            if (newValue) {
                if (existingUpdates[providerID] != true) {
                    existingUpdates[providerID] = true
                    changed = true
                }
            } else {
                if (existingUpdates.remove(providerID) != null) {
                    changed = true
                }
            }
        }

        if (changed) {
            ProviderPreferences.saveUpdatesAvailable(context, existingUpdates)
            // Step 5: 广播通知 UI 刷新
            withContext(Dispatchers.Main) {
                val intent = android.content.Intent(ACTION_UPDATE_STATE_CHANGED)
                context.sendBroadcast(intent)
            }
            Log.i(TAG, "checkInstalledProvidersUpdate: update state changed, broadcast sent")
        } else {
            Log.i(TAG, "checkInstalledProvidersUpdate: no change in update state")
        }
    }

    /**
     * 查询单个供应商的最新 package_hash。
     * 返回 null 表示查询失败或无 hash 信息。
     */
    private suspend fun fetchLatestPackageHash(providerID: String): String? =
        withContext(Dispatchers.IO) {
            try {
                val url = URL("$BASE_URL/providers/$providerID")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    setRequestProperty("Cache-Control", "no-cache")
                }
                val code = conn.responseCode
                if (code !in 200..299) {
                    Log.w(TAG, "fetchLatestPackageHash: HTTP $code for $providerID")
                    return@withContext null
                }
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(body)
                if (!json.optBoolean("ok", false)) return@withContext null

                // package.package_hash 优先，provider.package_hash 为 fallback
                val packageHash = json.optJSONObject("package")?.optString("package_hash")
                    ?.takeIf { it.isNotEmpty() }
                val providerHash = json.optJSONObject("provider")?.optString("package_hash")
                    ?.takeIf { it.isNotEmpty() }
                packageHash ?: providerHash
            } catch (e: Exception) {
                Log.w(TAG, "fetchLatestPackageHash failed for $providerID: ${e.message}")
                null
            }
        }
}
