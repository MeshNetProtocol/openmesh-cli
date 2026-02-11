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

    deinit {
        unregister()
    }

    public func register() {
        unregister()
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
            self.observer = nil
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
                protocolConfiguration.includeAllNetworks = true
                protocolConfiguration.excludeLocalNetworks = await SharedPreferences.excludeLocalNetworks.get()
                if #available(iOS 16.4, macOS 13.3, *) {
                    protocolConfiguration.excludeAPNs = await SharedPreferences.excludeAPNs.get()
                    protocolConfiguration.excludeCellularServices = false
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

    // MARK: - Provider messages (PacketTunnelProvider.handleAppMessage)

    private func providerSession() throws -> NETunnelProviderSession {
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(domain: "com.meshflux", code: 7101, userInfo: [NSLocalizedDescriptionKey: "Missing NETunnelProviderSession"])
        }
        return session
    }

    /// Sends a JSON message to the running packet-tunnel provider and returns the decoded JSON response.
    /// Requires VPN to be connected.
    public func sendProviderMessageJSON(_ message: [String: Any]) async throws -> [String: Any] {
        let session = try providerSession()
        let data = try JSONSerialization.data(withJSONObject: message)

        let reply = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            do {
                try session.sendProviderMessage(data) { response in
                    guard let response else {
                        cont.resume(throwing: NSError(domain: "com.meshflux", code: 7102, userInfo: [NSLocalizedDescriptionKey: "Empty response from provider"]))
                        return
                    }
                    cont.resume(returning: response)
                }
            } catch {
                cont.resume(throwing: error)
            }
        }

        let obj = try JSONSerialization.jsonObject(with: reply, options: [.fragmentsAllowed])
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: "com.meshflux", code: 7103, userInfo: [NSLocalizedDescriptionKey: "Invalid provider response"])
        }
        return dict
    }

    /// Sends a JSON message to the provider without waiting for a reply (fire-and-forget).
    /// Requires VPN to be connected.
    public func sendProviderMessageJSONNoReply(_ message: [String: Any]) throws {
        let session = try providerSession()
        let data = try JSONSerialization.data(withJSONObject: message)
        try session.sendProviderMessage(data) { _ in }
    }

    /// Triggers a urltest inside the running extension and returns per-outbound delay(ms).
    public func requestURLTest() async throws -> [String: Int] {
        let dict = try await sendProviderMessageJSON(["action": "urltest"])
        if let ok = dict["ok"] as? Bool, ok {
            return dict["delays"] as? [String: Int] ?? [:]
        }
        let err = dict["error"] as? String ?? "unknown error"
        throw NSError(domain: "com.meshflux", code: 7104, userInfo: [NSLocalizedDescriptionKey: err])
    }

    /// Selects an outbound inside the running extension (selector group).
    public func requestSelectOutbound(groupTag: String, outboundTag: String) async throws {
        let dict = try await sendProviderMessageJSON(["action": "select_outbound", "group": groupTag, "outbound": outboundTag])
        if let ok = dict["ok"] as? Bool, ok {
            return
        }
        let err = dict["error"] as? String ?? "unknown error"
        throw NSError(domain: "com.meshflux", code: 7105, userInfo: [NSLocalizedDescriptionKey: err])
    }

    /// Asks the running extension to reload its config.
    public func requestReload() throws {
        try sendProviderMessageJSONNoReply(["action": "reload"])
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
        let expectedProvider = Variant.useSystemExtension ? Variant.systemExtensionBundleIdentifier : Variant.extensionBundleIdentifier
        let candidates = managers.filter { m in
            guard let proto = m.protocolConfiguration as? NETunnelProviderProtocol else { return false }
            return proto.providerBundleIdentifier == expectedProvider
        }
        if let active = candidates.first(where: { m in
            let s = m.connection.status
            return s == .connected || s == .connecting || s == .reasserting || s == .disconnecting
        }) {
            return ExtensionProfile(active)
        }
        if let manager = candidates.first {
            return ExtensionProfile(manager)
        }
        // Fallback: preserve previous behavior if we can't find a matching provider bundle ID.
        return ExtensionProfile(managers[0])
    }

    /// Load profile for the manager whose `localizedDescription` matches (e.g. "MeshFlux VPN"). Uses notification-driven status only (no polling).
    public static func load(localizedDescription: String) async -> ExtensionProfile? {
        await withCheckedContinuation { cont in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let expectedProvider = Variant.useSystemExtension ? Variant.systemExtensionBundleIdentifier : Variant.extensionBundleIdentifier
                let all = managers ?? []
                let providerMatches = all.filter { m in
                    guard let proto = m.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                    return proto.providerBundleIdentifier == expectedProvider
                }

                // Prefer the currently active configuration when duplicates exist.
                let active = providerMatches.first(where: { m in
                    let s = m.connection.status
                    return s == .connected || s == .connecting || s == .reasserting || s == .disconnecting
                })

                let byDescription = providerMatches.first(where: { $0.localizedDescription == localizedDescription })
                let manager = active ?? byDescription ?? providerMatches.first
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
