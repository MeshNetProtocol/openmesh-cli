package com.meshnetprotocol.android.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import androidx.core.content.ContextCompat

class OpenMeshVpnService : VpnService() {
    private val localBinder = LocalBinder()
    private lateinit var notification: OpenMeshServiceNotification

    inner class LocalBinder : Binder() {
        fun currentState(): VpnServiceState = VpnStateMachine.currentState()
        fun startVpn() = startVpnSession()
        fun stopVpn() = stopVpnSession()
    }

    override fun onCreate() {
        super.onCreate()
        notification = OpenMeshServiceNotification(this)
        notification.ensureChannel()
        publishState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpnSession()
            else -> startVpnSession()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent): IBinder? {
        val systemBinder = super.onBind(intent)
        return systemBinder ?: localBinder
    }

    override fun onRevoke() {
        stopVpnSession()
    }

    override fun onDestroy() {
        VpnStateMachine.forceState(VpnServiceState.STOPPED)
        publishState()
        super.onDestroy()
    }

    private fun startVpnSession() {
        val current = VpnStateMachine.currentState()
        if (current == VpnServiceState.STARTED || current == VpnServiceState.STARTING) {
            startForeground(
                OpenMeshServiceNotification.NOTIFICATION_ID,
                notification.build(current),
            )
            return
        }

        if (!VpnStateMachine.transitionTo(VpnServiceState.STARTING)) {
            return
        }
        publishState()
        startForeground(
            OpenMeshServiceNotification.NOTIFICATION_ID,
            notification.build(VpnStateMachine.currentState()),
        )

        // Phase 0 skeleton: keep lifecycle and state transitions in place.
        VpnStateMachine.transitionTo(VpnServiceState.STARTED)
        publishState()
        startForeground(
            OpenMeshServiceNotification.NOTIFICATION_ID,
            notification.build(VpnStateMachine.currentState()),
        )
    }

    private fun stopVpnSession() {
        val current = VpnStateMachine.currentState()
        if (current == VpnServiceState.STOPPED) {
            stopSelf()
            return
        }

        if (!VpnStateMachine.transitionTo(VpnServiceState.STOPPING)) {
            return
        }
        publishState()

        // Phase 0 skeleton: real box service teardown is added in later phases.
        stopForeground(STOP_FOREGROUND_REMOVE)

        VpnStateMachine.forceState(VpnServiceState.STOPPED)
        publishState()
        stopSelf()
    }

    private fun publishState() {
        val event = Intent(ACTION_STATE_CHANGED)
            .setPackage(packageName)
            .putExtra(EXTRA_STATE_NAME, VpnStateMachine.currentState().name)
        sendBroadcast(event)
    }

    companion object {
        const val ACTION_START = "com.meshnetprotocol.android.action.START_VPN"
        const val ACTION_STOP = "com.meshnetprotocol.android.action.STOP_VPN"
        const val ACTION_STATE_CHANGED = "com.meshnetprotocol.android.action.VPN_STATE_CHANGED"
        const val EXTRA_STATE_NAME = "state_name"

        fun start(context: Context) {
            val intent = Intent(context, OpenMeshVpnService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, OpenMeshVpnService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }
}
