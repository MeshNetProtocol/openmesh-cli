package com.meshnetprotocol.android.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.IpPrefix
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.content.ContextCompat
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.vpn.command.CommandBridge
import java.net.InetAddress

class OpenMeshVpnService : VpnService() {
    private val localBinder = LocalBinder()
    private lateinit var notification: OpenMeshServiceNotification
    private lateinit var boxService: OpenMeshBoxService
    private lateinit var commandBridge: CommandBridge

    inner class LocalBinder : Binder() {
        fun currentState(): VpnServiceState = VpnStateMachine.currentState()
        fun startVpn() = startVpnSession()
        fun stopVpn() = stopVpnSession()
        fun executeCommand(commandJson: String): String = commandBridge.execute(commandJson)
    }

    override fun onCreate() {
        super.onCreate()
        notification = OpenMeshServiceNotification(this)
        notification.ensureChannel()
        boxService = OpenMeshBoxService(this, ProfileRepository(this))
        commandBridge = CommandBridge(boxService)
        publishState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpnSession()
            ACTION_COMMAND -> {
                val commandJson = intent.getStringExtra(EXTRA_COMMAND_JSON)
                if (!commandJson.isNullOrBlank()) {
                    handleCommand(commandJson)
                }
            }
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
        boxService.stop()
        VpnStateMachine.forceState(VpnServiceState.STOPPED)
        publishState()
        super.onDestroy()
    }

    fun openTun(options: OpenMeshTunOptions): ParcelFileDescriptor {
        if (prepare(this) != null) {
            error("Missing VPN permission")
        }

        val builder = Builder()
            .setSession("OpenMesh")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        for (address in options.inet4Address) {
            builder.addAddress(address.address, address.prefix)
        }
        for (address in options.inet6Address) {
            builder.addAddress(address.address, address.prefix)
        }

        if (options.autoRoute) {
            builder.addDnsServer(options.dnsServerAddress)

            if (options.inet4RouteAddress.isNotEmpty()) {
                for (route in options.inet4RouteAddress) {
                    builder.addRoute(route.address, route.prefix)
                }
            } else if (options.inet4Address.isNotEmpty()) {
                builder.addRoute("0.0.0.0", 0)
            }

            if (options.inet6RouteAddress.isNotEmpty()) {
                for (route in options.inet6RouteAddress) {
                    builder.addRoute(route.address, route.prefix)
                }
            } else if (options.inet6Address.isNotEmpty()) {
                builder.addRoute("::", 0)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                for (route in options.inet4RouteExcludeAddress) {
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(route.address), route.prefix))
                }
                for (route in options.inet6RouteExcludeAddress) {
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(route.address), route.prefix))
                }
            }

            for (pkg in options.includePackage) {
                try {
                    builder.addAllowedApplication(pkg)
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
            for (pkg in options.excludePackage) {
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
        }

        val pfd = builder.establish() ?: error("Failed to establish VPN tunnel")
        Log.i(TAG, "openTun established fd=${pfd.fd} dns=${options.dnsServerAddress}")
        return pfd
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

        val result = boxService.start()
        if (!result.ok) {
            Log.e(TAG, "startVpnSession failed: ${result.errorMessage}")
            boxService.stop()
            stopForeground(STOP_FOREGROUND_REMOVE)
            VpnStateMachine.forceState(VpnServiceState.STOPPED)
            publishState(result.errorMessage)
            stopSelf()
            return
        }

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
        boxService.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)

        VpnStateMachine.forceState(VpnServiceState.STOPPED)
        publishState()
        stopSelf()
    }

    private fun handleCommand(commandJson: String) {
        val resultJson = commandBridge.execute(commandJson)
        val event = Intent(ACTION_COMMAND_RESULT)
            .setPackage(packageName)
            .putExtra(EXTRA_COMMAND_JSON, commandJson)
            .putExtra(EXTRA_COMMAND_RESULT_JSON, resultJson)
        sendBroadcast(event)
    }

    private fun publishState(errorMessage: String? = null) {
        val event = Intent(ACTION_STATE_CHANGED)
            .setPackage(packageName)
            .putExtra(EXTRA_STATE_NAME, VpnStateMachine.currentState().name)

        if (!errorMessage.isNullOrBlank()) {
            event.putExtra(EXTRA_ERROR_MESSAGE, errorMessage)
        }
        sendBroadcast(event)
    }

    companion object {
        private const val TAG = "OpenMeshVpnService"

        const val ACTION_START = "com.meshnetprotocol.android.action.START_VPN"
        const val ACTION_STOP = "com.meshnetprotocol.android.action.STOP_VPN"
        const val ACTION_COMMAND = "com.meshnetprotocol.android.action.COMMAND"
        const val ACTION_STATE_CHANGED = "com.meshnetprotocol.android.action.VPN_STATE_CHANGED"
        const val ACTION_COMMAND_RESULT = "com.meshnetprotocol.android.action.COMMAND_RESULT"

        const val EXTRA_STATE_NAME = "state_name"
        const val EXTRA_ERROR_MESSAGE = "error_message"
        const val EXTRA_COMMAND_JSON = "command_json"
        const val EXTRA_COMMAND_RESULT_JSON = "command_result_json"

        fun start(context: Context) {
            val intent = Intent(context, OpenMeshVpnService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, OpenMeshVpnService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }

        fun sendCommand(context: Context, commandJson: String) {
            val intent = Intent(context, OpenMeshVpnService::class.java)
                .setAction(ACTION_COMMAND)
                .putExtra(EXTRA_COMMAND_JSON, commandJson)
            context.startService(intent)
        }
    }
}
