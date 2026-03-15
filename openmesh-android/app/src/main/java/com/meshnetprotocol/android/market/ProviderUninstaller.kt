package com.meshnetprotocol.android.market

import android.content.Context
import android.content.Intent
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.data.provider.ProviderStorageManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 卸载步骤枚举
 */
enum class UninstallStep { VALIDATE, REMOVE_PROFILE, REMOVE_PREFERENCES, REMOVE_FILES, FINALIZE }

/**
 * 卸载进度数据类
 */
data class UninstallProgress(val step: UninstallStep, val message: String)

/**
 * 卸载结果
 */
sealed class UninstallResult {
    object Success : UninstallResult()
    data class Failure(val step: UninstallStep, val error: String) : UninstallResult()
}

/**
 * 供应商卸载逻辑后端。
 * 对应 iOS 的 ProviderUninstaller.uninstall()。
 */
object ProviderUninstaller {

    suspend fun uninstall(
        context: Context,
        providerID: String,
        vpnConnected: Boolean,
        onProgress: (UninstallProgress) -> Unit
    ): UninstallResult = withContext(Dispatchers.IO) {
        try {
            // Step 1: VALIDATE
            onProgress(UninstallProgress(UninstallStep.VALIDATE, "检查当前连接状态"))
            if (vpnConnected) {
                val vpnPrefs = context.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
                val currentProviderID = vpnPrefs.getString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, "")
                if (currentProviderID == providerID) {
                    return@withContext UninstallResult.Failure(
                        UninstallStep.VALIDATE,
                        "当前 provider 正在被 VPN 使用，请先断开 VPN 再卸载"
                    )
                }
            }
            onProgress(UninstallProgress(UninstallStep.VALIDATE, "验证通过"))

            // Step 2: REMOVE_PROFILE
            onProgress(UninstallProgress(UninstallStep.REMOVE_PROFILE, "删除 Profile 记录"))
            val vpnPrefs = context.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
            val currentProviderID = vpnPrefs.getString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, "")
            if (currentProviderID == providerID) {
                vpnPrefs.edit()
                    .remove(ProfileRepository.KEY_SELECTED_PROFILE_ID)
                    .remove(ProfileRepository.KEY_SELECTED_PROFILE_NAME)
                    .remove(ProfileRepository.KEY_SELECTED_PROFILE_PATH)
                    .remove(ProfileRepository.KEY_SELECTED_PROVIDER_ID)
                    .apply()
            }
            onProgress(UninstallProgress(UninstallStep.REMOVE_PROFILE, "完成"))

            // Step 3: REMOVE_PREFERENCES
            onProgress(UninstallProgress(UninstallStep.REMOVE_PREFERENCES, "清理偏好映射"))
            ProviderPreferences.removeInstalledPackageHash(context, providerID)
            val updates = ProviderPreferences.getUpdatesAvailable(context).toMutableMap()
            if (updates.containsKey(providerID)) {
                updates.remove(providerID)
                ProviderPreferences.saveUpdatesAvailable(context, updates)
            }
            onProgress(UninstallProgress(UninstallStep.REMOVE_PREFERENCES, "完成"))

            // Step 4: REMOVE_FILES
            onProgress(UninstallProgress(UninstallStep.REMOVE_FILES, "删除缓存文件"))
            val storageManager = ProviderStorageManager(context)
            storageManager.deleteProvider(providerID)
            onProgress(UninstallProgress(UninstallStep.REMOVE_FILES, "完成"))

            // Step 5: FINALIZE
            onProgress(UninstallProgress(UninstallStep.FINALIZE, "完成"))

            // 广播 UI 刷新
            withContext(Dispatchers.Main) {
                val intent = Intent(UpdateChecker.ACTION_UPDATE_STATE_CHANGED)
                context.sendBroadcast(intent)
            }

            UninstallResult.Success
        } catch (e: Exception) {
            UninstallResult.Failure(UninstallStep.FINALIZE, "卸载失败：${e.message}")
        }
    }
}
