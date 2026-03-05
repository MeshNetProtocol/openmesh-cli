package com.meshnetprotocol.android

import android.app.Application
import com.meshnetprotocol.android.vpn.OpenMeshServiceNotification

class OpenMeshApp : Application() {
    override fun onCreate() {
        super.onCreate()
        OpenMeshServiceNotification(this).ensureChannel()
    }
}
