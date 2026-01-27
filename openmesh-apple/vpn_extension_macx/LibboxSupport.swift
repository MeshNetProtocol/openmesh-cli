
import Foundation
import Network
import NetworkExtension
import OpenMeshGo

//
// Copied from vpn_extension_macos/LibboxSupport.swift
//

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

    public func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32) throws -> OMLibboxConnectionOwner {
        throw NSError(domain: "com.meshflux", code: 1001, userInfo: [NSLocalizedDescriptionKey: "findConnectionOwner not implemented"])
    }

    // Copy sing-box logic as closely as possible.
    public func openTun(_ options: OMLibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        let now = Date()
        NSLog("MeshFlux System VPN: ===== openTun CALLED BY GO BACKEND =====")
        NSLog("MeshFlux System VPN: openTun called (synchronous entry point, thread=%@, t=%f)", Thread.current, now.timeIntervalSince1970)
        NSLog("MeshFlux System VPN: openTun options: autoRoute=%@, mtu=%d", String(describing: options?.getAutoRoute()), options?.getMTU() ?? -1)
        do {
            let start = Date()
            try runBlocking { [self] in
                NSLog("MeshFlux System VPN: openTun entering runBlocking (thread=%@, t=%f)", Thread.current, Date().timeIntervalSince1970)
                try await openTun0(options, ret0_)
                NSLog("MeshFlux System VPN: openTun0 returned to runBlocking caller (thread=%@, t=%f)", Thread.current, Date().timeIntervalSince1970)
            }
            let end = Date()
            NSLog("MeshFlux System VPN: openTun runBlocking duration = %.3f seconds", end.timeIntervalSince(start))
            NSLog("MeshFlux System VPN: openTun completed successfully, tunFd=%d", ret0_?.pointee ?? -1)
            NSLog("MeshFlux System VPN: ===== openTun COMPLETED SUCCESSFULLY =====")
        } catch {
            NSLog("MeshFlux System VPN: ===== openTun FAILED =====")
            NSLog("MeshFlux System VPN: ERROR openTun failed: %@", String(describing: error))
            if let nsError = error as NSError? {
                NSLog("MeshFlux System VPN: ERROR NSError domain: %@, code: %d, userInfo: %@", nsError.domain, nsError.code, nsError.userInfo)
            }
            throw error
        }
    }

    private func openTun0(_ options: OMLibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        let openTun0Start = Date()
        NSLog("MeshFlux System VPN: ===== openTun0 STARTED ===== (thread=%@, t=%f)", Thread.current, openTun0Start.timeIntervalSince1970)
        guard let options else {
            NSLog("MeshFlux System VPN: openTun0 ERROR - options is nil")
            throw NSError(domain: "nil options", code: 0)
        }
        guard let ret0_ else { 
            NSLog("MeshFlux System VPN: openTun0 ERROR - ret0_ pointer is nil")
            throw NSError(domain: "nil return pointer", code: 0)
        }

        NSLog("MeshFlux System VPN openTun: autoRoute=%@ mtu=%d httpProxy=%@", String(describing: options.getAutoRoute()), options.getMTU(), String(describing: options.isHTTPProxyEnabled()))

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
            if ipv4Address.isEmpty {
                NSLog("MeshFlux VPN extension openTun: WARNING no IPv4 address assigned")
            }

            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            var ipv4ExcludeRoutes: [NEIPv4Route] = []

            let inet4RouteAddressIterator = options.getInet4RouteAddress()!
            if inet4RouteAddressIterator.hasNext() {
                while inet4RouteAddressIterator.hasNext() {
                    let ipv4RoutePrefix = inet4RouteAddressIterator.next()!
                    ipv4Routes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
                }
            } else {
                ipv4Routes.append(NEIPv4Route.default())
            }

            let inet4RouteExcludeAddressIterator = options.getInet4RouteExcludeAddress()!
            while inet4RouteExcludeAddressIterator.hasNext() {
                let ipv4RoutePrefix = inet4RouteExcludeAddressIterator.next()!
                ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
            }
            
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
            
            let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
            var ipv6Routes: [NEIPv6Route] = []
            var ipv6ExcludeRoutes: [NEIPv6Route] = []

            let inet6RouteAddressIterator = options.getInet6RouteAddress()!
            if inet6RouteAddressIterator.hasNext() {
                while inet6RouteAddressIterator.hasNext() {
                    let ipv6RoutePrefix = inet6RouteAddressIterator.next()!
                    ipv6Routes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
                }
            } else {
                ipv6Routes.append(NEIPv6Route.default())
            }

            let inet6RouteExcludeAddressIterator = options.getInet6RouteExcludeAddress()!
            while inet6RouteExcludeAddressIterator.hasNext() {
                let ipv6RoutePrefix = inet6RouteExcludeAddressIterator.next()!
                ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
            }
            
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
        }

        networkSettings = settings
        let applySettingsStart = Date()
        NSLog("MeshFlux System VPN: ===== setTunnelNetworkSettings BEGIN =====")
        NSLog("MeshFlux System VPN: setTunnelNetworkSettings begin (thread=%@, t=%f)", Thread.current, applySettingsStart.timeIntervalSince1970)
        NSLog("MeshFlux System VPN: settings.mtu=%@", settings.mtu ?? "nil")
        NSLog("MeshFlux System VPN: settings.ipv4Settings=%@", settings.ipv4Settings != nil ? "present" : "nil")
        NSLog("MeshFlux System VPN: settings.ipv6Settings=%@", settings.ipv6Settings != nil ? "present" : "nil")
        NSLog("MeshFlux System VPN: settings.dnsSettings=%@", settings.dnsSettings != nil ? "present" : "nil")
        NSLog("MeshFlux System VPN: settings.proxySettings=%@", settings.proxySettings != nil ? "present" : "nil")
        do {
            // Force flush before setTunnelNetworkSettings
            fflush(stdout)
            fflush(stderr)
            try await tunnel.setTunnelNetworkSettings(settings)
            // Force flush after completion
            fflush(stdout)
            fflush(stderr)
            let applySettingsEnd = Date()
            NSLog("MeshFlux System VPN: setTunnelNetworkSettings completed successfully (duration=%.3f seconds)", applySettingsEnd.timeIntervalSince(applySettingsStart))
            NSLog("MeshFlux System VPN: ===== setTunnelNetworkSettings COMPLETED =====")
            // Force flush again
            fflush(stdout)
            fflush(stderr)
        } catch {
            let applySettingsEnd = Date()
            NSLog("MeshFlux System VPN: ===== setTunnelNetworkSettings FAILED ===== (duration=%.3f seconds)", applySettingsEnd.timeIntervalSince(applySettingsStart))
            NSLog("MeshFlux System VPN: ERROR setTunnelNetworkSettings failed: %@", String(describing: error))
            if let nsError = error as NSError? {
                NSLog("MeshFlux System VPN: ERROR NSError domain: %@, code: %d, userInfo: %@", nsError.domain, nsError.code, nsError.userInfo)
            }
            throw error
        }
        
        let tunFdStart = Date()
        NSLog("MeshFlux System VPN: ===== GETTING TUN FILE DESCRIPTOR ===== (thread=%@, t=%f)", Thread.current, tunFdStart.timeIntervalSince1970)
        NSLog("MeshFlux System VPN: Checking packetFlow.socket.fileDescriptor...")
        NSLog("MeshFlux System VPN: packetFlow type: %@", String(describing: type(of: tunnel.packetFlow)))
        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            let tunFdEnd = Date()
            NSLog("MeshFlux System VPN: ===== TUN FILE DESCRIPTOR OBTAINED: %d ===== (via packetFlow.socket, duration=%.3f seconds)", tunFd, tunFdEnd.timeIntervalSince(tunFdStart))
            NSLog("MeshFlux System VPN openTun: tunFd=%d (packetFlow.socket)", tunFd)
            NSLog("MeshFlux System VPN: Setting ret0_.pointee = %d", tunFd)
            ret0_.pointee = tunFd
            let openTun0End = Date()
            NSLog("MeshFlux System VPN: ===== openTun0 COMPLETED SUCCESSFULLY ===== (total duration=%.3f seconds)", openTun0End.timeIntervalSince(openTun0Start))
            // Force flush before return
            fflush(stdout)
            fflush(stderr)
            return
        } else {
            NSLog("MeshFlux System VPN: packetFlow.socket.fileDescriptor is nil or not Int32 (thread=%@)", Thread.current)
            NSLog("MeshFlux System VPN: packetFlow description: %@", String(describing: tunnel.packetFlow))
        }

        let tunFdLoopStart = Date()
        NSLog("MeshFlux System VPN: Attempting OMLibboxGetTunnelFileDescriptor()...")
        let tunFdFromLoop = OMLibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            let tunFdLoopEnd = Date()
            NSLog("MeshFlux System VPN: ===== TUN FILE DESCRIPTOR OBTAINED: %d ===== (via OMLibboxGetTunnelFileDescriptor, duration=%.3f seconds)", tunFdFromLoop, tunFdLoopEnd.timeIntervalSince(tunFdLoopStart))
            NSLog("MeshFlux System VPN openTun: tunFd=%d (OMLibboxGetTunnelFileDescriptor)", tunFdFromLoop)
            NSLog("MeshFlux System VPN: Setting ret0_.pointee = %d", tunFdFromLoop)
            ret0_.pointee = tunFdFromLoop
            let openTun0End = Date()
            NSLog("MeshFlux System VPN: ===== openTun0 COMPLETED SUCCESSFULLY ===== (total duration=%.3f seconds)", openTun0End.timeIntervalSince(openTun0Start))
            // Force flush before return
            fflush(stdout)
            fflush(stderr)
            return
        } else {
            let tunFdLoopEnd = Date()
            NSLog("MeshFlux System VPN: OMLibboxGetTunnelFileDescriptor() returned -1 (duration=%.3f seconds)", tunFdLoopEnd.timeIntervalSince(tunFdLoopStart))
        }

        let openTun0End = Date()
        NSLog("MeshFlux System VPN: ===== TUN FILE DESCRIPTOR OBTAINED: FAILED =====")
        NSLog("MeshFlux System VPN: openTun0 total duration before failure: %.3f seconds", openTun0End.timeIntervalSince(openTun0Start))
        NSLog("MeshFlux System VPN openTun: ERROR - missing tun file descriptor")
        throw NSError(domain: "missing file descriptor", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get TUN file descriptor from both packetFlow and OMLibboxGetTunnelFileDescriptor"])
    }

    // MARK: - OMLibboxCommandServerHandlerProtocol
    public func serviceStop() throws {}
    public func serviceReload() throws {}

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
        try runBlocking { [self] in
            try await tunnel.setTunnelNetworkSettings(settings)
        }
    }

    public func writeDebugMessage(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        NSLog("MeshFlux VPN extension libbox: %@", message)
        // Check if message contains keywords related to TUN or openTun
        if message.lowercased().contains("tun") || message.lowercased().contains("open") {
            NSLog("MeshFlux System VPN libbox: [TUN-RELATED] %@", message)
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
