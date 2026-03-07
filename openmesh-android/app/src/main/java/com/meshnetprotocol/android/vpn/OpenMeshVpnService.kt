package com.meshnetprotocol.android.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.IpPrefix
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.OsConstants
import android.util.Log
import java.net.NetworkInterface
import java.net.Inet6Address
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
import kotlinx.coroutines.*
import java.io.File

/**
 * OpenMesh VPN Service
 * 实现 libbox.PlatformInterface，处理 Go 引擎的回调
 */
class OpenMeshVpnService : VpnService(), PlatformInterface {
    private val localBinder = LocalBinder()
    private lateinit var notification: OpenMeshServiceNotification
    private lateinit var boxService: OpenMeshBoxService
    private lateinit var commandBridge: CommandBridge
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

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
        serviceScope.cancel()
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

        // 限制 MTU 以避免网络包过大被丢弃（Android 网络通常 MTU 为 1500）
        val vpnMtu = if (options.mtu > 0 && options.mtu <= 1500) options.mtu else 1500
        val builder = Builder()
            .setSession("OpenMesh")
            .setMtu(vpnMtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        // 1. IP Addresses
        val v4 = options.inet4Address
        while (v4.hasNext()) {
            val addr = v4.next()
            Log.i(TAG, "openTun: adding v4 address: ${addr.address()}/${addr.prefix()}")
            builder.addAddress(addr.address(), addr.prefix())
        }
        val v6 = options.inet6Address
        while (v6.hasNext()) {
            val addr = v6.next()
            Log.i(TAG, "openTun: adding v6 address: ${addr.address()}/${addr.prefix()}")
            builder.addAddress(addr.address(), addr.prefix())
        }

        // 2. Routing and DNS
        if (options.autoRoute) {
            val dnsAddr = options.dnsServerAddress.getValue()
            Log.i(TAG, "openTun: autoRoute enabled, adding DNS server: $dnsAddr")
            builder.addDnsServer(dnsAddr)
            builder.addSearchDomain("internal")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.inet4RouteAddress
                if (r4.hasNext()) {
                    while (r4.hasNext()) {
                        val r = r4.next()
                        addMaskedRoute(builder, r.address(), r.prefix())
                    }
                } else if (options.inet4Address.hasNext()) {
                    Log.i(TAG, "openTun: adding default v4 route 0.0.0.0/0")
                    builder.addRoute("0.0.0.0", 0)
                }

                val r6 = options.inet6RouteAddress
                if (r6.hasNext()) {
                    while (r6.hasNext()) {
                        val r = r6.next()
                        addMaskedRoute(builder, r.address(), r.prefix())
                    }
                } else if (options.inet6Address.hasNext()) {
                    Log.i(TAG, "openTun: adding default v6 route ::/0")
                    builder.addRoute("::", 0)
                }

                // Excludes (API 33+)
                val e4 = options.inet4RouteExcludeAddress
                while (e4.hasNext()) {
                    val r = e4.next()
                    Log.i(TAG, "openTun: excluding v4 route: ${r.address()}/${r.prefix()}")
                    excludeMaskedRoute(builder, r.address(), r.prefix())
                }
                
                try {
                    val e6 = options.inet6RouteExcludeAddress
                    while (e6.hasNext()) {
                        val r = e6.next()
                        Log.i(TAG, "openTun: excluding v6 route: ${r.address()}/${r.prefix()}")
                        excludeMaskedRoute(builder, r.address(), r.prefix())
                    }
                } catch (_: Exception) {}

            } else {
                val r4 = options.inet4RouteRange
                if (r4.hasNext()) {
                    while (r4.hasNext()) {
                        val r = r4.next()
                        addMaskedRoute(builder, r.address(), r.prefix())
                    }
                } else if (options.inet4Address.hasNext()) {
                    Log.i(TAG, "openTun: adding default v4 route 0.0.0.0/0")
                    builder.addRoute("0.0.0.0", 0)
                }

                val r6 = options.inet6RouteRange
                if (r6.hasNext()) {
                    while (r6.hasNext()) {
                        val r = r6.next()
                        addMaskedRoute(builder, r.address(), r.prefix())
                    }
                } else if (options.inet6Address.hasNext()) {
                    Log.i(TAG, "openTun: adding default v6 route ::/0")
                    builder.addRoute("::", 0)
                }
            }
        }


        // 高级配置对齐 (对齐 iOS/SFA)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            builder.setBlocking(true)
        }
        builder.allowBypass()
        // 排除应用自身流量，防止死循环
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {}

        val pfd = builder.establish() ?: error("Failed to establish TUN")
        currentTunFd = pfd
        
        // 设置底层网络，帮助系统正确路由受保护的 Socket
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.activeNetwork?.let { setUnderlyingNetworks(arrayOf(it)) }
        } catch (_: Exception) {}

        Log.i(TAG, "openTun: established, fd=${pfd.fd}, mtu=$vpnMtu")
        return pfd.fd
    }


    override fun autoDetectInterfaceControl(fd: Int) {
        Log.i("VPN_DEBUG", "autoDetectInterfaceControl called for fd: $fd")
        val result = protect(fd)
        if (!result) {
            Log.w(TAG, "protect(fd=$fd) failed")
        }
    }
    
    override fun usePlatformAutoDetectInterfaceControl(): Boolean {
        Log.i("VPN_DEBUG", "usePlatformAutoDetectInterfaceControl called")
        return true
    }
    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
    override fun underNetworkExtension(): Boolean {
        Log.i("VPN_DEBUG", "underNetworkExtension called")
        return true
    }


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


    private var providersObserver: android.os.FileObserver? = null

    private fun startRulesWatcher() {
        val providersDir = File(filesDir, "providers")
        if (!providersDir.exists()) providersDir.mkdirs()

        // Android 10+ (API 29+) 建议使用 File 版本的构造函数
        val observer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            object : android.os.FileObserver(providersDir, MODIFY or CREATE or DELETE) {
                override fun onEvent(event: Int, path: String?) {
                    handleFSEvent(path)
                }
            }
        } else {
            @Suppress("DEPRECATION")
            object : android.os.FileObserver(providersDir.absolutePath, MODIFY or CREATE or DELETE) {
                override fun onEvent(event: Int, path: String?) {
                    handleFSEvent(path)
                }
            }
        }
        
        observer.startWatching()
        providersObserver = observer
        Log.i(TAG, "Rules watcher started on: ${providersDir.absolutePath}")
    }

    private fun handleFSEvent(path: String?) {
        // 对齐 iOS: 当 providers 目录下文件变动时触发 reload
        if (path == null) return
        Log.d(TAG, "FSEvent detected: $path")
        
        // 简单去抖处理：避免频繁触发
        serviceScope.launch {
            delay(500)
            boxService.serviceReload()
        }
    }

    private fun stopRulesWatcher() {
        providersObserver?.stopWatching()
        providersObserver = null
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        // 告知引擎当前的默认物理接口
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = cm.activeNetwork
        val caps = cm.getNetworkCapabilities(activeNetwork)
        val linkProps = cm.getLinkProperties(activeNetwork)
        
        if (linkProps != null && caps != null) {
            val interfaceName = linkProps.interfaceName ?: "wlan0"
            // 查找真实的接口 index（对齐 iOS: 必须传真实 index，不能传 0）
            val realIndex = try {
                java.net.NetworkInterface.getByName(interfaceName)?.index ?: 0
            } catch (_: Exception) { 0 }
            Log.i(TAG, "Default network detected: $interfaceName (index=$realIndex)")
            val isExpensive = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            val isConstrained = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                !caps.hasCapability(25)
            } else {
                false
            }
            listener?.updateDefaultInterface(interfaceName, realIndex, isExpensive, isConstrained)
        }
    }
    
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {}

    override fun getInterfaces(): NetworkInterfaceIterator {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val networks = cm.allNetworks
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        
        for (network in networks) {
            val linkProps = cm.getLinkProperties(network) ?: continue
            val caps = cm.getNetworkCapabilities(network) ?: continue
            val interfaceName = linkProps.interfaceName ?: continue
            if (interfaceName == "tun0" || interfaceName.startsWith("tun")) continue
            
            val ni = try {
                NetworkInterface.getByName(interfaceName)
            } catch (e: Exception) {
                null
            } ?: continue
            
            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = interfaceName
            boxInterface.index = ni.index
            
            // DNS servers
            val dnsServers = linkProps.dnsServers.mapNotNull { it.hostAddress }
            boxInterface.dnsServer = object : StringIterator {
                private val it = dnsServers.iterator()
                override fun len(): Int = dnsServers.size
                override fun hasNext(): Boolean = it.hasNext()
                override fun next(): String = it.next()
            }
            
            // Type
            boxInterface.type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> libbox.Libbox.InterfaceTypeWIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> libbox.Libbox.InterfaceTypeCellular
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> libbox.Libbox.InterfaceTypeEthernet
                else -> libbox.Libbox.InterfaceTypeOther
            }
            
            // Addresses
            val addrs = ni.interfaceAddresses.mapNotNull { ifAddr ->
                val addr = ifAddr.address
                if (addr == null || addr.isLoopbackAddress || addr.isLinkLocalAddress) return@mapNotNull null
                var hostAddr = addr.hostAddress ?: return@mapNotNull null
                if (hostAddr.contains("%")) hostAddr = hostAddr.substringBefore("%")
                "$hostAddr/${ifAddr.networkPrefixLength}"
            }
            boxInterface.addresses = object : StringIterator {
                private val it = addrs.iterator()
                override fun len(): Int = addrs.size
                override fun hasNext(): Boolean = it.hasNext()
                override fun next(): String = it.next()
            }
            
            // Flags
            var flags = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (ni.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (ni.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (ni.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            boxInterface.flags = flags
            
            // MTU
            try {
                boxInterface.mtu = ni.mtu
            } catch (_: Exception) {}
            
            // Metered
            boxInterface.metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            
            interfaces.add(boxInterface)
        }

        return object : NetworkInterfaceIterator {
            private val iter = interfaces.iterator()
            override fun hasNext(): Boolean = iter.hasNext()
            override fun next(): LibboxNetworkInterface? = if (iter.hasNext()) iter.next() else null
        }
    }



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
        
        try {
            startRulesWatcher()
            val result = boxService.start()
            if (!result.ok) {
                Log.e(TAG, "boxService start failed: ${result.errorMessage}")
                stopVpnSession()
                publishState(result.errorMessage)
                return
            }
            VpnStateMachine.transitionTo(VpnServiceState.STARTED)
            publishState()
            startForeground(OpenMeshServiceNotification.NOTIFICATION_ID, notification.build(VpnServiceState.STARTED))
        } catch (t: Throwable) {
            Log.e(TAG, "Start VPN exception", t)
            stopVpnSession()
            publishState(t.message)
        }
    }

    private fun stopVpnSession() {
        if (!VpnStateMachine.transitionTo(VpnServiceState.STOPPING)) return
        publishState()
        
        stopRulesWatcher()
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

    // 对齐 iOS: 使用分段路由替代 0.0.0.0/0
    private fun ipv4DefaultSplitRoutes() = listOf(
        Route("1.0.0.0", 8),
        Route("2.0.0.0", 7),
        Route("4.0.0.0", 6),
        Route("8.0.0.0", 5),
        Route("16.0.0.0", 4),
        Route("32.0.0.0", 3),
        Route("64.0.0.0", 2),
        Route("128.0.0.0", 1)
    )

    private fun ipv6DefaultSplitRoutes() = listOf(
        Route("100::", 8),
        Route("200::", 7),
        Route("400::", 6),
        Route("800::", 5),
        Route("1000::", 4),
        Route("2000::", 3),
        Route("4000::", 2),
        Route("8000::", 1)
    )

    private data class Route(val address: String, val prefix: Int)

    private fun getNetworkAddress(address: String, prefixLength: Int): java.net.InetAddress {
        return try {
            val inetAddress = java.net.InetAddress.getByName(address)
            val bytes = inetAddress.address
            var remainingBits = prefixLength
            for (i in bytes.indices) {
                if (remainingBits >= 8) {
                    remainingBits -= 8
                } else if (remainingBits > 0) {
                    val mask = (0xFF shl (8 - remainingBits)).toByte()
                    bytes[i] = (bytes[i].toInt() and mask.toInt()).toByte()
                    remainingBits = 0
                } else {
                    bytes[i] = 0
                }
            }
            java.net.InetAddress.getByAddress(bytes)
        } catch (e: Exception) {
            java.net.InetAddress.getByName(address)
        }
    }

    private fun addMaskedRoute(builder: Builder, address: String, prefix: Int) {
        try {
            val netAddr = getNetworkAddress(address, prefix)
            if (netAddr.isLoopbackAddress) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                builder.addRoute(android.net.IpPrefix(netAddr, prefix))
            } else {
                builder.addRoute(netAddr.hostAddress ?: address, prefix)
            }
        } catch (e: Exception) {
            Log.w(TAG, "addMaskedRoute skipped for $address/$prefix: ${e.message}")
        }
    }

    private fun excludeMaskedRoute(builder: Builder, address: String, prefix: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                val netAddr = getNetworkAddress(address, prefix)
                if (netAddr.isLoopbackAddress) return
                builder.excludeRoute(android.net.IpPrefix(netAddr, prefix))
            } catch (e: Exception) {
                Log.w(TAG, "excludeMaskedRoute skipped for $address/$prefix: ${e.message}")
            }
        }
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
