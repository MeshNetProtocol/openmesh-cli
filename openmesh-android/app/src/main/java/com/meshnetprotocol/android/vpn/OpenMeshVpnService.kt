package com.meshnetprotocol.android.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.annotation.TargetApi
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.IpPrefix
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
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

        // Android 上底层引擎建议 MTU 为 1400（对齐大多数移动网络和物理网卡）
        val vpnMtu = if (options.mtu > 0) options.mtu else 1400
        val builder = Builder()
            .setSession("OpenMesh")
            .setMtu(vpnMtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val v4Addresses = mutableListOf<Route>()
        val v4 = options.inet4Address
        while (v4.hasNext()) {
            val addr = v4.next()
            v4Addresses.add(Route(addr.address(), addr.prefix()))
        }

        val v6Addresses = mutableListOf<Route>()
        val v6 = options.inet6Address
        while (v6.hasNext()) {
            val addr = v6.next()
            v6Addresses.add(Route(addr.address(), addr.prefix()))
        }

        val v4RouteAddresses = mutableListOf<Route>()
        val inet4RouteAddress = options.inet4RouteAddress
        while (inet4RouteAddress.hasNext()) {
            val route = inet4RouteAddress.next()
            v4RouteAddresses.add(Route(route.address(), route.prefix()))
        }

        val v6RouteAddresses = mutableListOf<Route>()
        val inet6RouteAddress = options.inet6RouteAddress
        while (inet6RouteAddress.hasNext()) {
            val route = inet6RouteAddress.next()
            v6RouteAddresses.add(Route(route.address(), route.prefix()))
        }

        val v4RouteExcludes = mutableListOf<Route>()
        val inet4RouteExcludeAddress = options.inet4RouteExcludeAddress
        while (inet4RouteExcludeAddress.hasNext()) {
            val route = inet4RouteExcludeAddress.next()
            v4RouteExcludes.add(Route(route.address(), route.prefix()))
        }

        val v6RouteExcludes = mutableListOf<Route>()
        val inet6RouteExcludeAddress = options.inet6RouteExcludeAddress
        while (inet6RouteExcludeAddress.hasNext()) {
            val route = inet6RouteExcludeAddress.next()
            v6RouteExcludes.add(Route(route.address(), route.prefix()))
        }

        val v4RouteRanges = mutableListOf<Route>()
        val inet4RouteRange = options.inet4RouteRange
        while (inet4RouteRange.hasNext()) {
            val route = inet4RouteRange.next()
            v4RouteRanges.add(Route(route.address(), route.prefix()))
        }

        val v6RouteRanges = mutableListOf<Route>()
        val inet6RouteRange = options.inet6RouteRange
        while (inet6RouteRange.hasNext()) {
            val route = inet6RouteRange.next()
            v6RouteRanges.add(Route(route.address(), route.prefix()))
        }

        val includePackages = mutableListOf<String>()
        val includePackage = options.includePackage
        while (includePackage.hasNext()) {
            includePackages += includePackage.next()
        }

        val excludePackages = mutableListOf<String>()
        val excludePackage = options.excludePackage
        while (excludePackage.hasNext()) {
            excludePackages += excludePackage.next()
        }

        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val underlyingNetwork = OpenMeshDefaultNetworkMonitor.currentOrSelect(this)
        val underlyingInterface = OpenMeshDefaultNetworkMonitor.interfaceName(cm, underlyingNetwork)
        val underlyingIpv6Available =
            OpenMeshDefaultNetworkMonitor.hasUsableIpv6(cm, underlyingNetwork)

        Log.i(
            TAG,
            "openTun: route stats v4RouteAddress=${v4RouteAddresses.size} v4RouteRange=${v4RouteRanges.size} v4Exclude=${v4RouteExcludes.size} v6RouteAddress=${v6RouteAddresses.size} v6RouteRange=${v6RouteRanges.size} v6Exclude=${v6RouteExcludes.size} include=${includePackages.size} exclude=${excludePackages.size} underlying=${underlyingInterface ?: "<none>"} ipv6Available=$underlyingIpv6Available"
        )

        // 1. IP Addresses
        for (addr in v4Addresses) {
            Log.i(TAG, "openTun: adding v4 address: ${addr.address}/${addr.prefix}")
            builder.addAddress(addr.address, addr.prefix)
        }
        if (underlyingIpv6Available) {
            for (addr in v6Addresses) {
                Log.i(TAG, "openTun: adding v6 address: ${addr.address}/${addr.prefix}")
                builder.addAddress(addr.address, addr.prefix)
            }
        } else if (v6Addresses.isNotEmpty()) {
            Log.i(TAG, "openTun: skip v6 addresses because underlying network has no usable IPv6")
        }

        // 2. Routing and DNS
        if (options.autoRoute) {
            val dnsAddr = options.dnsServerAddress.getValue()
            Log.i(TAG, "openTun: autoRoute enabled, adding DNS server: $dnsAddr")
            builder.addDnsServer(dnsAddr)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (v4RouteAddresses.isNotEmpty()) {
                    for (route in v4RouteAddresses) {
                        addMaskedRoute(builder, route.address, route.prefix)
                    }
                } else if (v4RouteRanges.isNotEmpty()) {
                    Log.i(TAG, "openTun: API33+ fallback to v4 route ranges (${v4RouteRanges.size})")
                    for (route in v4RouteRanges) {
                        addMaskedRoute(builder, route.address, route.prefix)
                    }
                } else if (v4Addresses.isNotEmpty()) {
                    Log.i(TAG, "openTun: adding default v4 route 0.0.0.0/0")
                    builder.addRoute("0.0.0.0", 0)
                    // 添加调试日志确认所有流量都进入 VPN
                    Log.i(TAG, "VPN_DEBUG: Default route added - all IPv4 traffic will enter VPN tunnel")
                }

                if (underlyingIpv6Available) {
                    if (v6RouteAddresses.isNotEmpty()) {
                        for (route in v6RouteAddresses) {
                            addMaskedRoute(builder, route.address, route.prefix)
                        }
                    } else if (v6RouteRanges.isNotEmpty()) {
                        Log.i(TAG, "openTun: API33+ fallback to v6 route ranges (${v6RouteRanges.size})")
                        for (route in v6RouteRanges) {
                            addMaskedRoute(builder, route.address, route.prefix)
                        }
                    } else if (v6Addresses.isNotEmpty()) {
                        Log.i(TAG, "openTun: adding default v6 route ::/0")
                        builder.addRoute("::", 0)
                    }
                } else if (v6RouteAddresses.isNotEmpty() || v6RouteRanges.isNotEmpty()) {
                    Log.i(TAG, "openTun: skip v6 routes because underlying network has no usable IPv6")
                }

                // Excludes (API 33+)
                if (v4RouteExcludes.isEmpty()) {
                    Log.i(TAG, "VPN_DEBUG: No v4 route excludes found in config.")
                }
                for (route in v4RouteExcludes) {
                    Log.i(TAG, "VPN_DEBUG: [ACTION] excluding v4 route: ${route.address}/${route.prefix}")
                    excludeMaskedRoute(builder, route.address, route.prefix)
                }
                
                if (underlyingIpv6Available) {
                    for (route in v6RouteExcludes) {
                        Log.i(TAG, "VPN_DEBUG: [ACTION] excluding v6 route: ${route.address}/${route.prefix}")
                        excludeMaskedRoute(builder, route.address, route.prefix)
                    }
                } else if (v6RouteExcludes.isNotEmpty()) {
                    Log.i(TAG, "openTun: skip v6 excludes because underlying network has no usable IPv6")
                }

            } else {
                if (v4RouteRanges.isNotEmpty()) {
                    for (route in v4RouteRanges) {
                        addMaskedRoute(builder, route.address, route.prefix)
                    }
                }

                if (underlyingIpv6Available) {
                    if (v6RouteRanges.isNotEmpty()) {
                        for (route in v6RouteRanges) {
                            addMaskedRoute(builder, route.address, route.prefix)
                        }
                    }
                } else if (v6RouteRanges.isNotEmpty()) {
                    Log.i(TAG, "openTun: skip legacy v6 routes because underlying network has no usable IPv6")
                }
            }
        }


        // 高级配置对齐 (对齐 iOS/SFA)
        // 去除了 setBlocking(true)，因为 sing-box 底层引擎(Go)假设 fd 是非阻塞的。如果设为 blocking 会严重干扰 TCP。

        if (includePackages.isNotEmpty()) {
            for (pkg in includePackages) {
                try {
                    builder.addAllowedApplication(pkg)
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
        }

        if (excludePackages.isNotEmpty()) {
            for (pkg in excludePackages) {
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
        }

        val pfd = builder.establish() ?: error("Failed to establish TUN")
        currentTunFd = pfd

        Log.i(TAG, "openTun: established, fd=${pfd.fd}, mtu=$vpnMtu")
        return pfd.fd
    }


    override fun autoDetectInterfaceControl(fd: Int) {
        // 重要调试日志：如果这里没有打印，说明 direct outbound 没在 protect socket，会导致回环崩溃
        Log.i("VPN_PROTECT", "autoDetectInterfaceControl: protecting fd $fd")
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
        Log.i("VPN_DEBUG", "underNetworkExtension called -> returning false")
        return false
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
                // Log.v(TAG, "findConnectionOwner fallback needed? ${e.message}")
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

    private var defaultNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var monitoredDefaultNetwork: Network? = null

    private fun updateDefaultInterfaceInfo(cm: ConnectivityManager, network: Network?, listener: InterfaceUpdateListener?) {
        if (network == null) {
            OpenMeshDefaultNetworkMonitor.clear()
            listener?.updateDefaultInterface("", -1, false, false)
            return
        }
        val caps = cm.getNetworkCapabilities(network)
        val linkProps = cm.getLinkProperties(network)
        if (caps != null && linkProps != null) {
            OpenMeshDefaultNetworkMonitor.update(network)
            val interfaceName = linkProps.interfaceName ?: ""
            val realIndex = try {
                java.net.NetworkInterface.getByName(interfaceName)?.index ?: 0
            } catch (_: Exception) { 0 }
            
            val isExpensive = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            val isConstrained = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                !caps.hasCapability(25) // NET_CAPABILITY_NOT_VCN_MANAGED mapped to 25 if not available
            } else {
                false
            }
            listener?.updateDefaultInterface(interfaceName, realIndex, isExpensive, isConstrained)
            Log.d(TAG, "Default network updated: $interfaceName (index=$realIndex)")
        } else {
            OpenMeshDefaultNetworkMonitor.clear()
            listener?.updateDefaultInterface("", -1, false, false)
        }
    }

    private fun buildDefaultNetworkRequest(): NetworkRequest {
        val builder = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        if (Build.VERSION.SDK_INT == Build.VERSION_CODES.M) {
            builder.removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            builder.removeCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
        }
        return builder.build()
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        closeDefaultInterfaceMonitor(listener)

        val initialNetwork = OpenMeshDefaultNetworkMonitor.selectUnderlyingNetwork(cm)
        monitoredDefaultNetwork = initialNetwork
        updateDefaultInterfaceInfo(cm, initialNetwork, listener)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        if (!OpenMeshDefaultNetworkMonitor.isUsableUnderlyingNetwork(cm, network)) {
                            return
                        }
                        monitoredDefaultNetwork = network
                        updateDefaultInterfaceInfo(cm, network, listener)
                    }

                    override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                        if (!OpenMeshDefaultNetworkMonitor.isUsableUnderlyingNetwork(cm, network)) {
                            if (monitoredDefaultNetwork == network) {
                                val fallback = OpenMeshDefaultNetworkMonitor.selectUnderlyingNetwork(cm)
                                monitoredDefaultNetwork = fallback
                                updateDefaultInterfaceInfo(cm, fallback, listener)
                            }
                            return
                        }
                        monitoredDefaultNetwork = network
                        updateDefaultInterfaceInfo(cm, network, listener)
                    }

                    override fun onLost(network: Network) {
                        if (monitoredDefaultNetwork == network) {
                            val fallback = OpenMeshDefaultNetworkMonitor.selectUnderlyingNetwork(cm)
                            monitoredDefaultNetwork = fallback
                            updateDefaultInterfaceInfo(cm, fallback, listener)
                            Log.d(TAG, "Default network lost; fallback=${fallback != null}")
                        }
                    }
                }
                val handler = Handler(Looper.getMainLooper())
                val request = buildDefaultNetworkRequest()
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                        registerBestMatchingNetworkCallbackCompat(cm, request, callback, handler)
                        Log.i(TAG, "startDefaultInterfaceMonitor: registered best-matching network callback")
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> {
                        cm.requestNetwork(request, callback, handler)
                        Log.i(TAG, "startDefaultInterfaceMonitor: registered requestNetwork callback")
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                        cm.registerDefaultNetworkCallback(callback, handler)
                        Log.i(TAG, "startDefaultInterfaceMonitor: registered default network callback with handler")
                    }
                    else -> {
                        cm.registerDefaultNetworkCallback(callback)
                        Log.i(TAG, "startDefaultInterfaceMonitor: registered default network callback")
                    }
                }
                defaultNetworkCallback = callback
            } catch (e: Exception) {
                Log.e(TAG, "startDefaultInterfaceMonitor: failed to register callback", e)
                val fallback = OpenMeshDefaultNetworkMonitor.selectUnderlyingNetwork(cm)
                monitoredDefaultNetwork = fallback
                updateDefaultInterfaceInfo(cm, fallback, listener)
            }
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        defaultNetworkCallback?.let {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            try {
                cm.unregisterNetworkCallback(it)
                Log.i(TAG, "closeDefaultInterfaceMonitor: unregistered DefaultNetworkCallback")
            } catch (e: Exception) {
                Log.e(TAG, "closeDefaultInterfaceMonitor: failed to unregister callback", e)
            }
            defaultNetworkCallback = null
            monitoredDefaultNetwork = null
            OpenMeshDefaultNetworkMonitor.clear()
        }
    }

    @TargetApi(Build.VERSION_CODES.S)
    private fun registerBestMatchingNetworkCallbackCompat(
        cm: ConnectivityManager,
        request: NetworkRequest,
        callback: ConnectivityManager.NetworkCallback,
        handler: Handler
    ) {
        cm.registerBestMatchingNetworkCallback(request, callback, handler)
    }

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
    override fun localDNSTransport(): LocalDNSTransport? {
        LocalResolver.appContext = this
        return LocalResolver
    }
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
            com.meshnetprotocol.android.vpn.command.GroupCommandClient.connect()
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
        com.meshnetprotocol.android.vpn.command.GroupCommandClient.disconnect()
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
