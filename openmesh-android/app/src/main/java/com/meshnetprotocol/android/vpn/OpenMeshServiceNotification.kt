package com.meshnetprotocol.android.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.meshnetprotocol.android.MainActivity
import com.meshnetprotocol.android.R

class OpenMeshServiceNotification(private val context: Context) {

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "OpenMesh VPN runtime"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    fun build(state: VpnServiceState): Notification {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(context.getString(R.string.vpn_notification_title))
            .setContentText(textForState(state))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(state == VpnServiceState.STARTING || state == VpnServiceState.STARTED)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun textForState(state: VpnServiceState): String {
        return when (state) {
            VpnServiceState.STOPPED -> context.getString(R.string.vpn_state_stopped)
            VpnServiceState.STARTING -> context.getString(R.string.vpn_state_starting)
            VpnServiceState.STARTED -> context.getString(R.string.vpn_state_started)
            VpnServiceState.STOPPING -> context.getString(R.string.vpn_state_stopping)
        }
    }

    companion object {
        const val CHANNEL_ID = "openmesh_vpn_runtime"
        const val CHANNEL_NAME = "OpenMesh VPN"
        const val NOTIFICATION_ID = 1001
    }
}
