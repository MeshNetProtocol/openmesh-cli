import Foundation
import Network
import NetworkExtension
import OpenMeshGo

final class OpenMeshLibboxPlatformInterface: NSObject, OMLibboxPlatformInterfaceProtocol, OMLibboxCommandServerHandlerProtocol {
    private let tunnel: PacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var nwMonitor: NWPathMonitor?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    // MARK: - OMLibboxPlatformInterfaceProtocol
    public func underNetworkExtension() -> Bool { true }
    public func includeAllNetworks() -> Bool { false }
    public func useProcFS() -> Bool { false }
    public func usePlatformAutoDetectControl() -> Bool { false }
    public func autoDetectControl(_: Int32) throws {}
    public func clearDNSCache() {}
    public func localDNSTransport() -> OMLibboxLocalDNSTransportProtocol? { nil }
    public func systemCertificates() -> OMLibboxStringIteratorProtocol? { EmptyStringIterator() }
    public func readWIFIState() -> OMLibboxWIFIState? { nil }
    public func send(_ notification: OMLibboxNotification?) throws {}

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
        EmptyNetworkInterfaceIterator()
    }

    public func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32) throws -> OMLibboxConnectionOwner {
        throw NSError(domain: "com.openmesh", code: 1001, userInfo: [NSLocalizedDescriptionKey: "findConnectionOwner not implemented"])
    }

    public func openTun(_ options: OMLibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else { throw NSError(domain: "com.openmesh", code: 1002) }
        guard let ret0_ else { throw NSError(domain: "com.openmesh", code: 1003) }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            if let dnsServer = try? options.getDNSServerAddress() {
                let dnsSettings = NEDNSSettings(servers: [dnsServer.value])
                dnsSettings.matchDomains = [""]
                dnsSettings.matchDomainsNoSearch = true
                settings.dnsSettings = dnsSettings
            }

            // IPv4
            var ipv4Addresses: [String] = []
            var ipv4Masks: [String] = []
            if let ipv4AddressIterator = options.getInet4Address() {
                while ipv4AddressIterator.hasNext() {
                    if let prefix = ipv4AddressIterator.next() {
                        ipv4Addresses.append(prefix.address())
                        ipv4Masks.append(prefix.mask())
                    }
                }
            }
            if !ipv4Addresses.isEmpty {
                let ipv4 = NEIPv4Settings(addresses: ipv4Addresses, subnetMasks: ipv4Masks)
                ipv4.includedRoutes = collectIPv4Routes(options.getInet4RouteRange()) ?? [NEIPv4Route.default()]
                ipv4.excludedRoutes = collectIPv4Routes(options.getInet4RouteExcludeAddress()) ?? []
                settings.ipv4Settings = ipv4
            }

            // IPv6
            var ipv6Addresses: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            if let ipv6AddressIterator = options.getInet6Address() {
                while ipv6AddressIterator.hasNext() {
                    if let prefix = ipv6AddressIterator.next() {
                        ipv6Addresses.append(prefix.address())
                        ipv6Prefixes.append(NSNumber(value: prefix.prefix()))
                    }
                }
            }
            if !ipv6Addresses.isEmpty {
                let ipv6 = NEIPv6Settings(addresses: ipv6Addresses, networkPrefixLengths: ipv6Prefixes)
                ipv6.includedRoutes = collectIPv6Routes(options.getInet6RouteRange()) ?? [NEIPv6Route.default()]
                ipv6.excludedRoutes = collectIPv6Routes(options.getInet6RouteExcludeAddress()) ?? []
                settings.ipv6Settings = ipv6
            }
        }

        networkSettings = settings
        try runBlocking {
            try await self.tunnel.setTunnelNetworkSettings(settings)
        }

        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }
        throw NSError(domain: "com.openmesh", code: 1004, userInfo: [NSLocalizedDescriptionKey: "missing tunnel file descriptor"])
    }

    // MARK: - OMLibboxCommandServerHandlerProtocol
    public func serviceStop() throws {}

    public func serviceReload() throws {
        // Placeholder for future "reload config" support.
    }

    public func getSystemProxyStatus() throws -> OMLibboxSystemProxyStatus {
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
        try runBlocking {
            try await self.tunnel.setTunnelNetworkSettings(settings)
        }
    }

    public func writeDebugMessage(_: String?) {}

    // MARK: - Helpers
    func reset() {
        networkSettings = nil
    }

    private func collectIPv4Routes(_ it: OMLibboxRoutePrefixIteratorProtocol?) -> [NEIPv4Route]? {
        guard let it else { return nil }
        var routes: [NEIPv4Route] = []
        while it.hasNext() {
            if let p = it.next() {
                routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
            }
        }
        return routes.isEmpty ? nil : routes
    }

    private func collectIPv6Routes(_ it: OMLibboxRoutePrefixIteratorProtocol?) -> [NEIPv6Route]? {
        guard let it else { return nil }
        var routes: [NEIPv6Route] = []
        while it.hasNext() {
            if let p = it.next() {
                routes.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
            }
        }
        return routes.isEmpty ? nil : routes
    }
}

private func runBlocking(_ fn: @escaping @Sendable () async throws -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var capturedError: Error?
    Task.detached {
        do {
            try await fn()
        } catch {
            capturedError = error
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let capturedError { throw capturedError }
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
