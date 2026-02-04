import Foundation
import Network
import NetworkExtension
import OpenMeshGo
import VPNLibrary

final class OpenMeshLibboxPlatformInterface: NSObject, OMLibboxPlatformInterfaceProtocol, OMLibboxCommandServerHandlerProtocol {
    private let tunnel: ExtensionProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var nwMonitor: NWPathMonitor?

    init(_ tunnel: ExtensionProvider) {
        self.tunnel = tunnel
    }

    /// Split routes equivalent to 0.0.0.0/0; iOS often rejects a single default route.
    /// Matches sing-box Apple client (autoRouteUseSubRangesByDefault).
    private static func ipv4DefaultSplitRoutes() -> [NEIPv4Route] {
        [
            NEIPv4Route(destinationAddress: "1.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "2.0.0.0", subnetMask: "254.0.0.0"),
            NEIPv4Route(destinationAddress: "4.0.0.0", subnetMask: "252.0.0.0"),
            NEIPv4Route(destinationAddress: "8.0.0.0", subnetMask: "248.0.0.0"),
            NEIPv4Route(destinationAddress: "16.0.0.0", subnetMask: "240.0.0.0"),
            NEIPv4Route(destinationAddress: "32.0.0.0", subnetMask: "224.0.0.0"),
            NEIPv4Route(destinationAddress: "64.0.0.0", subnetMask: "192.0.0.0"),
            NEIPv4Route(destinationAddress: "128.0.0.0", subnetMask: "128.0.0.0"),
        ]
    }

    /// Split routes equivalent to ::/0; iOS often rejects a single default route.
    private static func ipv6DefaultSplitRoutes() -> [NEIPv6Route] {
        [
            NEIPv6Route(destinationAddress: "100::", networkPrefixLength: 8),
            NEIPv6Route(destinationAddress: "200::", networkPrefixLength: 7),
            NEIPv6Route(destinationAddress: "400::", networkPrefixLength: 6),
            NEIPv6Route(destinationAddress: "800::", networkPrefixLength: 5),
            NEIPv6Route(destinationAddress: "1000::", networkPrefixLength: 4),
            NEIPv6Route(destinationAddress: "2000::", networkPrefixLength: 3),
            NEIPv6Route(destinationAddress: "4000::", networkPrefixLength: 2),
            NEIPv6Route(destinationAddress: "8000::", networkPrefixLength: 1),
        ]
    }

    // MARK: - OMLibboxPlatformInterfaceProtocol
    public func underNetworkExtension() -> Bool { true }
    /// 与 Mac 一致：从 SharedPreferences 读取是否全局模式（App 在设置/Home 修改后生效）。
    public func includeAllNetworks() -> Bool {
        SharedPreferences.includeAllNetworks.getBlocking()
    }
    /// 与 Mac 一致：从 SharedPreferences 读取是否排除本地网络（App 在设置 Tab 修改后生效）。
    public func excludeLocalNetworks() -> Bool {
        SharedPreferences.excludeLocalNetworks.getBlocking()
    }
    public func useProcFS() -> Bool { false }
    public func usePlatformAutoDetectControl() -> Bool { false }
    public func autoDetectControl(_ fd: Int32) throws {}
    public func clearDNSCache() {}
    public func localDNSTransport() -> OMLibboxLocalDNSTransportProtocol? { nil }
    public func systemCertificates() -> OMLibboxStringIteratorProtocol? { EmptyStringIterator() }
    public func readWIFIState() -> OMLibboxWIFIState? { nil }
    public func send(_ notification: OMLibboxNotification?) throws {}
    public func packageName(byUid uid: Int32, error: NSErrorPointer) -> String { "" }
    public func uid(byPackageName packageName: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {}
    public func writeLog(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        NSLog("MeshFlux VPN extension libbox: %@", message)
    }

    public func startDefaultInterfaceMonitor(_ listener: OMLibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            self.onUpdateDefaultInterface(listener, path)
            semaphore.signal()
            monitor.pathUpdateHandler = { path in
                self.onUpdateDefaultInterface(listener, path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        semaphore.wait()
    }

    private func onUpdateDefaultInterface(_ listener: OMLibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
        if path.status == .unsatisfied {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        guard let defaultInterface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(defaultInterface.name, interfaceIndex: Int32(defaultInterface.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    public func closeDefaultInterfaceMonitor(_: OMLibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    public func getInterfaces() throws -> OMLibboxNetworkInterfaceIteratorProtocol {
        ensureNWMonitorStartedIfNeeded()
        guard let nwMonitor else {
            return NetworkInterfaceArrayIterator([])
        }
        let path = nwMonitor.currentPath
        if path.status == .unsatisfied {
            return NetworkInterfaceArrayIterator([])
        }
        var interfaces: [OMLibboxNetworkInterface] = []
        for it in path.availableInterfaces {
            let interface = OMLibboxNetworkInterface()
            interface.name = it.name
            interface.index = Int32(it.index)
            switch it.type {
            case .wifi:
                interface.type = 0
            case .cellular:
                interface.type = 1
            case .wiredEthernet:
                interface.type = 2
            default:
                interface.type = 3
            }
            interfaces.append(interface)
        }
        return NetworkInterfaceArrayIterator(interfaces)
    }

    private func ensureNWMonitorStartedIfNeeded() {
        if nwMonitor != nil { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak monitor] _ in
            semaphore.signal()
            monitor?.pathUpdateHandler = { _ in }
        }
        monitor.start(queue: DispatchQueue.global())
        _ = semaphore.wait(timeout: .now() + 2)
    }

    public func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32, ret0_: UnsafeMutablePointer<Int32>?) throws {
        ret0_?.pointee = -1
        throw NSError(domain: "com.meshflux", code: 1001, userInfo: [NSLocalizedDescriptionKey: "findConnectionOwner not implemented"])
    }

    // Copy sing-box logic as closely as possible.
    public func openTun(_ options: OMLibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTun0(options, ret0_)
        }
    }

    private func openTun0(_ options: OMLibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else { throw NSError(domain: "nil options", code: 0) }
        guard let ret0_ else { throw NSError(domain: "nil return pointer", code: 0) }

        NSLog("MeshFlux VPN extension openTun: autoRoute=%@ mtu=%d excludeLocalNetworks=%@ httpProxy=%@", String(describing: options.getAutoRoute()), options.getMTU(), excludeLocalNetworks() ? "true" : "false", String(describing: options.isHTTPProxyEnabled()))

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            do {
                let dnsServer = try options.getDNSServerAddress()
                NSLog("MeshFlux VPN extension openTun: dnsServer=%@", dnsServer.value)
                let dnsSettings = NEDNSSettings(servers: [dnsServer.value])
                dnsSettings.matchDomains = [""]
                dnsSettings.matchDomainsNoSearch = true
                settings.dnsSettings = dnsSettings
            } catch {
                NSLog("MeshFlux VPN extension openTun: ERROR getDNSServerAddress failed: %@", String(describing: error))
                // Best-effort: log inet4 addresses even if DNS server resolution fails.
                var addrs: [String] = []
                let it = options.getInet4Address()
                while it?.hasNext() == true {
                    if let p = it?.next() {
                        addrs.append("\(p.address())/\(p.prefix())")
                    }
                }
                NSLog("MeshFlux VPN extension openTun: inet4Address (best-effort) count=%d values=%@", addrs.count, addrs.joined(separator: ","))
                throw error
            }

            // IPv4
            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            let ipv4AddressIterator = options.getInet4Address()!
            while ipv4AddressIterator.hasNext() {
                let ipv4Prefix = ipv4AddressIterator.next()!
                ipv4Address.append(ipv4Prefix.address())
                ipv4Mask.append(ipv4Prefix.mask())
            }
            NSLog("MeshFlux VPN extension openTun: inet4Address.count=%d values=%@", ipv4Address.count, ipv4Address.joined(separator: ","))
            if ipv4Address.isEmpty {
                NSLog("MeshFlux VPN extension openTun: WARNING no IPv4 address assigned (DNS hijacking will fail)")
            } else if ipv4Mask.first == "255.255.255.255" {
                NSLog("MeshFlux VPN extension openTun: WARNING first IPv4 address is /32 (DNS hijacking will fail)")
            }

            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            var ipv4ExcludeRoutes: [NEIPv4Route] = []

            // On iOS, a single default route (0.0.0.0/0) often causes "failed to add an IPv4 route"
            // from nesessionmanager. Use split routes (same as sing-box SFI) so the system accepts them.
            let inet4RouteAddressIterator = options.getInet4RouteAddress()!
            if inet4RouteAddressIterator.hasNext() {
                while inet4RouteAddressIterator.hasNext() {
                    let ipv4RoutePrefix = inet4RouteAddressIterator.next()!
                    ipv4Routes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
                }
            } else {
                ipv4Routes.append(contentsOf: Self.ipv4DefaultSplitRoutes())
            }

            let inet4RouteExcludeAddressIterator = options.getInet4RouteExcludeAddress()!
            while inet4RouteExcludeAddressIterator.hasNext() {
                let ipv4RoutePrefix = inet4RouteExcludeAddressIterator.next()!
                ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
            }
            NSLog("MeshFlux VPN extension openTun: inet4Routes.included=%d excluded=%d", ipv4Routes.count, ipv4ExcludeRoutes.count)

            ipv4Settings.includedRoutes = ipv4Routes
            ipv4Settings.excludedRoutes = ipv4ExcludeRoutes
            settings.ipv4Settings = ipv4Settings

            // IPv6
            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            let ipv6AddressIterator = options.getInet6Address()!
            while ipv6AddressIterator.hasNext() {
                let ipv6Prefix = ipv6AddressIterator.next()!
                ipv6Address.append(ipv6Prefix.address())
                ipv6Prefixes.append(NSNumber(value: ipv6Prefix.prefix()))
            }
            NSLog("MeshFlux VPN extension openTun: inet6Address.count=%d values=%@", ipv6Address.count, ipv6Address.joined(separator: ","))

            let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
            var ipv6Routes: [NEIPv6Route] = []
            var ipv6ExcludeRoutes: [NEIPv6Route] = []

            // On iOS, a single default route (::/0) often causes "failed to add an IPv6 route".
            // Use split routes (same as sing-box SFI) so the system accepts them.
            let inet6RouteAddressIterator = options.getInet6RouteAddress()!
            if inet6RouteAddressIterator.hasNext() {
                while inet6RouteAddressIterator.hasNext() {
                    let ipv6RoutePrefix = inet6RouteAddressIterator.next()!
                    ipv6Routes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
                }
            } else {
                ipv6Routes.append(contentsOf: Self.ipv6DefaultSplitRoutes())
            }

            let inet6RouteExcludeAddressIterator = options.getInet6RouteExcludeAddress()!
            while inet6RouteExcludeAddressIterator.hasNext() {
                let ipv6RoutePrefix = inet6RouteExcludeAddressIterator.next()!
                ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
            }
            NSLog("MeshFlux VPN extension openTun: inet6Routes.included=%d excluded=%d", ipv6Routes.count, ipv6ExcludeRoutes.count)

            ipv6Settings.includedRoutes = ipv6Routes
            ipv6Settings.excludedRoutes = ipv6ExcludeRoutes
            settings.ipv6Settings = ipv6Settings
        }

        if options.isHTTPProxyEnabled() {
            let proxySettings = NEProxySettings()
            let proxyServer = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxySettings.httpServer = proxyServer
            proxySettings.httpsServer = proxyServer

            var bypassDomains: [String] = []
            let bypassDomainIterator = options.getHTTPProxyBypassDomain()!
            while bypassDomainIterator.hasNext() {
                bypassDomains.append(bypassDomainIterator.next())
            }
            if !bypassDomains.isEmpty {
                proxySettings.exceptionList = bypassDomains
            }

            var matchDomains: [String] = []
            let matchDomainIterator = options.getHTTPProxyMatchDomain()!
            while matchDomainIterator.hasNext() {
                matchDomains.append(matchDomainIterator.next())
            }
            if !matchDomains.isEmpty {
                proxySettings.matchDomains = matchDomains
            }
            settings.proxySettings = proxySettings
            NSLog("MeshFlux VPN extension openTun: proxy server=%@:%d bypass=%d match=%d", options.getHTTPProxyServer(), options.getHTTPProxyServerPort(), bypassDomains.count, matchDomains.count)
        }

        networkSettings = settings
        NSLog("MeshFlux VPN extension openTun: setTunnelNetworkSettings begin")
        try await tunnel.setTunnelNetworkSettings(settings)
        NSLog("MeshFlux VPN extension openTun: setTunnelNetworkSettings done")

        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            NSLog("MeshFlux VPN extension openTun: tunFd=%d (packetFlow.socket)", tunFd)
            ret0_.pointee = tunFd
            return
        }

        let tunFdFromLoop = OMLibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            NSLog("MeshFlux VPN extension openTun: tunFd=%d (OMLibboxGetTunnelFileDescriptor)", tunFdFromLoop)
            ret0_.pointee = tunFdFromLoop
            return
        }

        NSLog("MeshFlux VPN extension openTun: ERROR missing tun fd")
        throw NSError(domain: "missing file descriptor", code: 0)
    }

    // MARK: - OMLibboxCommandServerHandlerProtocol
    public func postServiceClose() {}
    public func serviceReload() throws {}

    public func getSystemProxyStatus() -> OMLibboxSystemProxyStatus? {
        let status = OMLibboxSystemProxyStatus()
        guard let settings = networkSettings else { return status }
        guard let proxySettings = settings.proxySettings else { return status }
        if proxySettings.httpServer == nil { return status }
        status.available = true
        status.enabled = proxySettings.httpEnabled
        return status
    }

    public func setSystemProxyEnabled(_ enabled: Bool) throws {
        guard let settings = networkSettings else { return }
        guard let proxySettings = settings.proxySettings else { return }
        if proxySettings.httpServer == nil { return }
        if proxySettings.httpEnabled == enabled { return }
        proxySettings.httpEnabled = enabled
        proxySettings.httpsEnabled = enabled
        settings.proxySettings = proxySettings
        try runBlocking { [self] in
            try await tunnel.setTunnelNetworkSettings(settings)
        }
    }

    // MARK: - Helpers
    func reset() {
        networkSettings = nil
    }
}

private func runBlocking<T>(_ tBlock: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached {
        do {
            box.result = .success(try await tBlock())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result.get()
}

private final class ResultBox<T> {
    var result: Result<T, Error>!
}

private final class EmptyStringIterator: NSObject, OMLibboxStringIteratorProtocol {
    func hasNext() -> Bool { false }
    func len() -> Int32 { 0 }
    func next() -> String { "" }
}

private final class EmptyNetworkInterfaceIterator: NSObject, OMLibboxNetworkInterfaceIteratorProtocol {
    func hasNext() -> Bool { false }
    func next() -> OMLibboxNetworkInterface? { nil }
}

private final class NetworkInterfaceArrayIterator: NSObject, OMLibboxNetworkInterfaceIteratorProtocol {
    private var iterator: IndexingIterator<[OMLibboxNetworkInterface]>
    private var nextValue: OMLibboxNetworkInterface?

    init(_ array: [OMLibboxNetworkInterface]) {
        iterator = array.makeIterator()
    }

    func hasNext() -> Bool {
        nextValue = iterator.next()
        return nextValue != nil
    }

    func next() -> OMLibboxNetworkInterface? {
        nextValue
    }
}
