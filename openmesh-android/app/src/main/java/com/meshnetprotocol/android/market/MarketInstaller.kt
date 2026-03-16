package com.meshnetprotocol.android.market

import android.content.Context
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.data.provider.ProviderStorageManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * 安装步骤枚
 */
enum class InstallStep {
    FETCH_DETAIL,
    DOWNLOAD_CONFIG,
    VALIDATE_CONFIG,
    DOWNLOAD_ROUTING_RULES,
    WRITE_ROUTING_RULES,
    DOWNLOAD_RULE_SET,
    WRITE_RULE_SET,
    WRITE_CONFIG,
    REGISTER_PROFILE,
    FINALIZE
}

/**
 * 安装进度数据类
 */
data class InstallProgress(
    val step: InstallStep,
    val message: String
)

/**
 * 安装结果数据类
 */
sealed class InstallResult {
    object Success : InstallResult()
    data class Failure(val step: InstallStep, val error: String) : InstallResult()
}

/**
 * 供应商在线安装逻辑后端
 */
object MarketInstaller {

    suspend fun installProvider(
        context: Context,
        provider: TrafficProvider,
        selectAfterInstall: Boolean,
        onProgress: (InstallProgress) -> Unit
    ): InstallResult = withContext(Dispatchers.IO) {
        val providerID = provider.id.let { 
            if (it.isEmpty()) "imported-${UUID.randomUUID().toString().take(8)}" else it 
        }
        
        try {
            // Step 1: FETCH_DETAIL
            onProgress(InstallProgress(InstallStep.FETCH_DETAIL, "读取供应商详情"))
            onProgress(InstallProgress(InstallStep.FETCH_DETAIL, "供应商 ID: $providerID"))

            // Fetch latest package_hash from detail endpoint (parity with iOS)
            var latestPackageHash: String? = null
            try {
                val detailUrl = URL("https://openmesh-api.ribencong.workers.dev/api/v1/providers/$providerID")
                val detailConn = (detailUrl.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    setRequestProperty("Cache-Control", "no-cache")
                }
                if (detailConn.responseCode in 200..299) {
                    val detailBody = detailConn.inputStream.bufferedReader().use { it.readText() }
                    val detailJson = JSONObject(detailBody)
                    if (detailJson.optBoolean("ok", false)) {
                        latestPackageHash = detailJson.optJSONObject("package")
                            ?.optString("package_hash")?.takeIf { it.isNotEmpty() }
                            ?: detailJson.optJSONObject("provider")
                                ?.optString("package_hash")?.takeIf { it.isNotEmpty() }
                    }
                }
                android.util.Log.i("MarketInstaller", "Fetched latest package_hash from detail: $latestPackageHash")
            } catch (e: Exception) {
                android.util.Log.w("MarketInstaller", "Failed to fetch detail for latest hash: ${e.message}")
            }

            // Step 2: DOWNLOAD_CONFIG
            onProgress(InstallProgress(InstallStep.DOWNLOAD_CONFIG, "下载配置文件: ${provider.config_url}"))
            val configBody = try {
                val url = URL(provider.config_url)
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 25000
                    readTimeout = 25000
                    doInput = true
                }
                
                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    return@withContext InstallResult.Failure(InstallStep.DOWNLOAD_CONFIG, "下载失败 (HTTP $responseCode)")
                }
                
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                if (body.isEmpty()) {
                    return@withContext InstallResult.Failure(InstallStep.DOWNLOAD_CONFIG, "下载失败: 响应内容为空")
                }
                onProgress(InstallProgress(InstallStep.DOWNLOAD_CONFIG, "下载完成, ${body.length} 字节"))
                body
            } catch (e: Exception) {
                return@withContext InstallResult.Failure(InstallStep.DOWNLOAD_CONFIG, "下载失败: ${e.message}")
            }

            // Step 3: VALIDATE_CONFIG
            onProgress(InstallProgress(InstallStep.VALIDATE_CONFIG, "解析配置文件"))
            try {
                JSONObject(configBody)
                onProgress(InstallProgress(InstallStep.VALIDATE_CONFIG, "配置验证通过"))
            } catch (e: Exception) {
                return@withContext InstallResult.Failure(InstallStep.VALIDATE_CONFIG, "JSON 解析失败: ${e.message}")
            }

            // Step 4: DOWNLOAD_ROUTING_RULES
            onProgress(InstallProgress(InstallStep.DOWNLOAD_ROUTING_RULES, "跳过: 该供应商未提供 routing_rules.json"))

            // Step 5: WRITE_ROUTING_RULES
            onProgress(InstallProgress(InstallStep.WRITE_ROUTING_RULES, "跳过"))

            // Step 6: DOWNLOAD_RULE_SET
            onProgress(InstallProgress(InstallStep.DOWNLOAD_RULE_SET, "跳过预下载: 已启用 sing-box 原生远程更新机制"))

            // Step 7: WRITE_RULE_SET
            onProgress(InstallProgress(InstallStep.WRITE_RULE_SET, "No local .srs written"))

            // Step 8: WRITE_CONFIG
            onProgress(InstallProgress(InstallStep.WRITE_CONFIG, "写入 config.json"))
            val storageManager = ProviderStorageManager(context)
            storageManager.writeFullConfig(providerID, configBody).onFailure {
                return@withContext InstallResult.Failure(InstallStep.WRITE_CONFIG, "写入失败: ${it.message}")
            }
            storageManager.writeConfig(providerID, configBody).onFailure {
                return@withContext InstallResult.Failure(InstallStep.WRITE_CONFIG, "写入失败: ${it.message}")
            }
            onProgress(InstallProgress(InstallStep.WRITE_CONFIG, "写入完成"))

            // Step 9: REGISTER_PROFILE
            onProgress(InstallProgress(InstallStep.REGISTER_PROFILE, "注册到供应商列表"))
            val configFile = storageManager.getConfigFile(providerID)
            val prefs = context.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
            if (selectAfterInstall) {
                val profileId = System.currentTimeMillis()
                prefs.edit()
                    .putLong(ProfileRepository.KEY_SELECTED_PROFILE_ID, profileId)
                    .putString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, provider.name)
                    .putString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, configFile.absolutePath)
                    .putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerID)
                    .apply()
                
                // 保存 providerID -> profileID 映射 (用于从已选 profile 反查 provider)
                com.meshnetprotocol.android.market.ProviderPreferences
                    .saveProviderForProfile(context, profileId, providerID)
                
                android.util.Log.i("MarketInstaller", "Selected new provider after install: $providerID")
            }
            
            onProgress(InstallProgress(InstallStep.REGISTER_PROFILE, "注册完成"))

            // 保存友好名称（用于 UI 展示）
            com.meshnetprotocol.android.market.ProviderPreferences
                .saveProviderName(context, providerID, provider.name)

            // 保存 package_hash（用于后续更新检查对比）
            // PARITY WITH iOS: Use the latest hash from detail endpoint first,
            // fallback to the provider list hash
            val packageHash = latestPackageHash
                ?: provider.package_hash
                ?: provider.provider_hash
                ?: ""
            if (packageHash.isNotEmpty()) {
                com.meshnetprotocol.android.market.ProviderPreferences
                    .saveInstalledPackageHash(context, providerID, packageHash)
                android.util.Log.i("MarketInstaller", "Saved package_hash for $providerID: $packageHash")
            }

            // PARITY WITH iOS: Clear the update flag after successful install
            // (iOS: MarketService.swift line 657-660)
            val currentUpdates = com.meshnetprotocol.android.market.ProviderPreferences
                .getUpdatesAvailable(context).toMutableMap()
            if (currentUpdates.remove(providerID) != null) {
                com.meshnetprotocol.android.market.ProviderPreferences
                    .saveUpdatesAvailable(context, currentUpdates)
                android.util.Log.i("MarketInstaller", "Cleared update flag for $providerID")
            }

            // Step 10: FINALIZE
            onProgress(InstallProgress(InstallStep.FINALIZE, "完成"))
            InstallResult.Success

        } catch (e: Exception) {
            InstallResult.Failure(InstallStep.FINALIZE, "安装过程中出现意外错误: ${e.message}")
        }
    }
}
