package com.meshnetprotocol.android.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Process
import android.util.Log
import androidx.core.content.ContextCompat
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.vpn.command.CommandBridge
import libbox.ConnectionOwner
import libbox.InterfaceUpdateListener
import libbox.LocalDNSTransport
import libbox.NetworkInterfaceIterator
import libbox.PlatformInterface
import libbox.StringIterator
import libbox.TunOptions
import libbox.WIFIState
import libbox.Notification as LibboxNotification
import java.net.InetAddress
import java.net.InetSocketAddress
import java.security.KeyStore
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import libbox.NetworkInterface as LibboxNetworkInterface

/**
 * OpenMesh VPN Service
 * 实现 libbox.PlatformInterface，处理 Go 引擎的回调
 */
class OpenMeshVpnService : VpnService(), PlatformInterface {
    private val localBinder = LocalBinder()
    private lateinit var notification: OpenMeshServiceNotification
    private lateinit var boxService: OpenMeshBoxService
    private lateinit var commandBridge: CommandBridge

    var currentTunFd: ParcelFileDescriptor? = null

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
                val command = intent.getStringExtra(EXTRA_COMMAND_JSON)
                if (!command.isNullOrBlank()) handleCommand(command)
            }
            else -> startVpnSession()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent): IBinder? = super.onBind(intent) ?: localBinder

    override fun onRevoke() = stopVpnSession()

    override fun onDestroy() {
        boxService.stop()
        VpnStateMachine.forceState(VpnServiceState.STOPPED)
        publishState()
        super.onDestroy()
    }

    fun stopSelfFromEngine() = stopVpnSession()

    // ======== PlatformInterface Implementation ========

    override fun openTun(options: TunOptions): Int {
        Log.i(TAG, "openTun mtu=${options.mtu} autoRoute=${options.autoRoute}")

        if (prepare(this) != null) error("VPN permission missing")

        val builder = Builder()
            .setSession("OpenMesh")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        // IPv4
        val v4 = options.inet4Address
        while (v4.hasNext()) {
            val addr = v4.next()
            builder.addAddress(addr.address(), addr.prefix())
        }

        // IPv6
        val v6 = options.inet6Address
        while (v6.hasNext()) {
            val addr = v6.next()
            builder.addAddress(addr.address(), addr.prefix())
        }

        if (options.autoRoute) {
            builder.addDnsServer(options.dnsServerAddress.value)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.inet4RouteAddress
                while (r4.hasNext()) {
                    val r = r4.next()
                    builder.addRoute(IpPrefix(InetAddress.getByName(r.address()), r.prefix()))
                }
                val r6 = options.inet6RouteAddress
                while (r6.hasNext()) {
                    val r = r6.next()
                    builder.addRoute(IpPrefix(InetAddress.getByName(r.address()), r.prefix()))
                }
                // Excludes
                val e4 = options.inet4RouteExcludeAddress
                while (e4.hasNext()) {
                    val r = e4.next()
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(r.address()), r.prefix()))
                }
            } else {
                val r4 = options.inet4RouteRange
                while (r4.hasNext()) {
                    val r = r4.next()
                    builder.addRoute(r.address(), r.prefix())
                }
                val r6 = options.inet6RouteRange
                while (r6.hasNext()) {
                    val r = r6.next()
                    builder.addRoute(r.address(), r.prefix())
                }
            }
        }

        val pfd = builder.establish() ?: error("Failed to establish TUN")
        currentTunFd = pfd
        return pfd.fd
    }

    override fun autoDetectInterfaceControl(fd: Int) { protect(fd) }
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int
    ): ConnectionOwner {
        val owner = ConnectionOwner()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val uid = cm.getConnectionOwnerUid(
                    ipProtocol,
                    InetSocketAddress(sourceAddress, sourcePort),
                    InetSocketAddress(destinationAddress, destinationPort)
                )
                if (uid != Process.INVALID_UID) {
                    owner.userId = uid
                    packageManager.getPackagesForUid(uid)?.firstOrNull()?.let {
                        owner.androidPackageName = it
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "findConnectionOwner failed", e)
            }
        }
        return owner
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {}
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {}

    override fun getInterfaces(): NetworkInterfaceIterator {
        return object : NetworkInterfaceIterator {
            override fun hasNext(): Boolean = false
            override fun next(): LibboxNetworkInterface? = null
        }
    }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun clearDNSCache() {}
    override fun readWIFIState(): WIFIState? = null
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun sendNotification(notification: LibboxNotification?) {}

    @OptIn(ExperimentalEncodingApi::class)
    override fun systemCertificates(): StringIterator {
        val certs = mutableListOf<String>()
        try {
            val ks = KeyStore.getInstance("AndroidCAStore").apply { load(null, null) }
            val aliases = ks.aliases()
            while (aliases.hasMoreElements()) {
                val cert = ks.getCertificate(aliases.nextElement())
                certs.add("-----BEGIN CERTIFICATE-----\n" + Base64.encode(cert.encoded) + "\n-----END CERTIFICATE-----")
            }
        } catch (_: Exception) {}
        return object : StringIterator {
            private val iter = certs.iterator()
            override fun len(): Int = certs.size
            override fun hasNext(): Boolean = iter.hasNext()
            override fun next(): String = iter.next()
        }
    }

    // ======== Management ========

    private fun startVpnSession() {
        if (!VpnStateMachine.transitionTo(VpnServiceState.STARTING)) return
        publishState()
        startForeground(OpenMeshServiceNotification.NOTIFICATION_ID, notification.build(VpnServiceState.STARTING))
        
        val result = boxService.start()
        if (!result.ok) {
            boxService.stop()
            VpnStateMachine.forceState(VpnServiceState.STOPPED)
            publishState(result.errorMessage)
            stopSelf()
            return
        }
        VpnStateMachine.transitionTo(VpnServiceState.STARTED)
        publishState()
        startForeground(OpenMeshServiceNotification.NOTIFICATION_ID, notification.build(VpnServiceState.STARTED))
    }

    private fun stopVpnSession() {
        if (!VpnStateMachine.transitionTo(VpnServiceState.STOPPING)) return
        publishState()
        boxService.stop()
        currentTunFd?.close()
        currentTunFd = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        VpnStateMachine.forceState(VpnServiceState.STOPPED)
        publishState()
        stopSelf()
    }

    private fun handleCommand(commandJson: String) {
        val result = commandBridge.execute(commandJson)
        sendBroadcast(Intent(ACTION_COMMAND_RESULT).apply {
            setPackage(packageName)
            putExtra(EXTRA_COMMAND_JSON, commandJson)
            putExtra(EXTRA_COMMAND_RESULT_JSON, result)
        })
    }

    private fun publishState(error: String? = null) {
        sendBroadcast(Intent(ACTION_STATE_CHANGED).apply {
            setPackage(packageName)
            putExtra(EXTRA_STATE_NAME, VpnStateMachine.currentState().name)
            error?.let { putExtra(EXTRA_ERROR_MESSAGE, it) }
        })
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
