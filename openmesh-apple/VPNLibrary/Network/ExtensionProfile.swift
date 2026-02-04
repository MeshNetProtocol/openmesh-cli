//
//  ExtensionProfile.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Network/ExtensionProfile.swift.
//  No Libbox in main app: stop() only calls manager.connection.stopVPNTunnel().
//

import Foundation
import NetworkExtension

public class ExtensionProfile: ObservableObject {
    public static let controlKind = "com.meshnetprotocol.OpenMesh.widget.ServiceToggle"

    private let manager: NEVPNManager
    private var connection: NEVPNConnection
    private var observer: Any?

    @Published public var status: NEVPNStatus

    public init(_ manager: NEVPNManager) {
        self.manager = manager
        connection = manager.connection
        status = manager.connection.status
    }

    public func register() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.connection = self.manager.connection
            self.status = self.connection.status
        }
    }

    private func unregister() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setOnDemandRules() {
        let interfaceRule = NEOnDemandRuleConnect()
        interfaceRule.interfaceTypeMatch = .any
        let probeRule = NEOnDemandRuleConnect()
        probeRule.probeURL = URL(string: "http://captive.apple.com")
        manager.onDemandRules = [interfaceRule, probeRule]
    }

    public func updateAlwaysOn(_ newState: Bool) async throws {
        manager.isOnDemandEnabled = newState
        setOnDemandRules()
        try await manager.saveToPreferences()
    }

    @available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
    public func fetchLastDisconnectError() async throws {
        try await connection.fetchLastDisconnectError()
    }

    public func start() async throws {
        await fetchProfile()
        manager.isEnabled = true
        if await SharedPreferences.alwaysOn.get() {
            manager.isOnDemandEnabled = true
            setOnDemandRules()
        }
        #if !os(tvOS)
            if let protocolConfiguration = manager.protocolConfiguration {
                let includeAllNetworks = await SharedPreferences.includeAllNetworks.get()
                protocolConfiguration.includeAllNetworks = includeAllNetworks
                protocolConfiguration.excludeLocalNetworks = await SharedPreferences.excludeLocalNetworks.get()
                if #available(iOS 16.4, macOS 13.3, *) {
                    protocolConfiguration.excludeAPNs = await SharedPreferences.excludeAPNs.get()
                    protocolConfiguration.excludeCellularServices = !includeAllNetworks
                }
                protocolConfiguration.enforceRoutes = await SharedPreferences.enforceRoutes.get()
            }
        #endif
        try await manager.saveToPreferences()
        #if os(macOS)
            if Variant.useSystemExtension {
                try manager.connection.startVPNTunnel(options: [
                    "username": NSString(string: NSUserName()),
                ])
                return
            }
        #endif
        try manager.connection.startVPNTunnel()
    }

    public func fetchProfile() async {
        do {
            let selectedID = await SharedPreferences.selectedProfileID.get()
            if let profile = try await ProfileManager.get(selectedID), profile.type == .icloud {
                _ = try profile.read()
            }
        } catch {}
    }

    public func stop() async throws {
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            try await manager.saveToPreferences()
        }
        // No Libbox/OpenMeshGo command client in main app; extension will receive stopTunnel and close service.
        manager.connection.stopVPNTunnel()
    }

    /// Wait until connection status becomes `.disconnected` or `.invalid`, or the given timeout elapses.
    /// Use after `stop()` before calling `start()` to avoid "Skip a start command: session in state disconnecting".
    public func waitUntilDisconnected(timeoutSeconds: TimeInterval = 20) async {
        let start = Date()
        let pollInterval: UInt64 = 200_000_000 // 0.2s
        while Date().timeIntervalSince(start) < timeoutSeconds {
            let s = await MainActor.run { connection.status }
            if s == .disconnected || s == .invalid {
                return
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
    }

    public static func load() async throws -> ExtensionProfile? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if managers.isEmpty { return nil }
        return ExtensionProfile(managers[0])
    }

    /// Load profile for the manager whose `localizedDescription` matches (e.g. "MeshFlux VPN"). Uses notification-driven status only (no polling).
    public static func load(localizedDescription: String) async -> ExtensionProfile? {
        await withCheckedContinuation { cont in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let manager = managers?.first { $0.localizedDescription == localizedDescription }
                cont.resume(returning: manager.map { ExtensionProfile($0) })
            }
        }
    }

    public static func install() async throws {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = Variant.applicationName
        let tunnelProtocol = NETunnelProviderProtocol()
        if Variant.useSystemExtension {
            tunnelProtocol.providerBundleIdentifier = Variant.systemExtensionBundleIdentifier
        } else {
            tunnelProtocol.providerBundleIdentifier = Variant.extensionBundleIdentifier
        }
        tunnelProtocol.serverAddress = "sing-box"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        try await manager.saveToPreferences()
    }
}
