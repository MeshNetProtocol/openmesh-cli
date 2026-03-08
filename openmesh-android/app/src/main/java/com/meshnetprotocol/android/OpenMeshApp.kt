package com.meshnetprotocol.android

import android.app.Application
import com.meshnetprotocol.android.core.GoEngine
import com.meshnetprotocol.android.data.provider.ProviderStorageManager
import com.meshnetprotocol.android.vpn.OpenMeshServiceNotification

class OpenMeshApp : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // 初始化 Go 引擎（必须在 Application onCreate 中调用）
        GoEngine.initialize(this)
        
        // 确保通知渠道已创建
        OpenMeshServiceNotification(this).ensureChannel()

        // 迁移已安装的 Provider（为旧 provider 创建 config_full.json）
        ProviderStorageManager(this).migrateInstalledProviders()
    }
}
