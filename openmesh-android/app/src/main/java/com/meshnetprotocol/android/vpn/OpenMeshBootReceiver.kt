package com.meshnetprotocol.android.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class OpenMeshBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // Phase 0 skeleton: reserve boot flow for future auto-reconnect logic.
            }
        }
    }
}
