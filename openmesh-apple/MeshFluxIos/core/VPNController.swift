//
//  VPNController.swift
//  MeshFluxIos
//
//  iOS VPN controller aligned with MeshFluxMac semantics:
//  - notification-driven status (no polling)
//  - provides start/stop/toggle and best-effort reload
//

import Combine
import Foundation
import NetworkExtension
import OpenMeshGo
import VPNLibrary

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isConnecting: Bool = false
    @Published private(set) var status: NEVPNStatus = .disconnected

    private let descriptionFallback = "MeshFlux VPN"
    private var profile: ExtensionProfile?
    private var statusCancellable: AnyCancellable?

    private let configNonce = UUID().uuidString

    func load() async {
        statusCancellable = nil
        profile = nil

        // Align with MeshFluxMac: always keep local networks excluded on iOS; no UI toggle.
        let excludeLocal = await SharedPreferences.excludeLocalNetworks.get()
        if excludeLocal == false {
            await SharedPreferences.excludeLocalNetworks.set(true)
        }

        if let manager = await loadManager() {
            let p = ExtensionProfile(manager)
            p.register()
            profile = p
            statusCancellable = p.$status
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newStatus in
                    self?.status = newStatus
                    self?.isConnected = (newStatus == .connected)
                    self?.isConnecting = (newStatus == .connecting || newStatus == .reasserting)
                }
            // Initialize immediately
            let s = p.status
            status = s
            isConnected = (s == .connected)
            isConnecting = (s == .connecting || s == .reasserting)

            if excludeLocal == false, isConnected {
                await reconnectToApplySettings()
            }
        } else {
            status = .disconnected
            isConnected = false
            isConnecting = false
        }
    }

    func toggleVPN() {
        Task { await toggleVPNAsync() }
    }

    func toggleVPNAsync() async {
        if status == .connected || status == .connecting || status == .reasserting {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        if profile == nil {
            await ensureManagerExists()
            await load()
        }
        guard let profile else { return }
        do {
            try await profile.start()
        } catch {
            NSLog("VPNController start failed: %@", String(describing: error))
        }
    }

    func stop() async {
        guard let profile else { return }
        do {
            try await profile.stop()
        } catch {
            NSLog("VPNController stop failed: %@", String(describing: error))
        }
    }

    /// Best-effort: asks the running extension to reload its config (picks up profile/rules changes).
    /// Uses command.sock path via libbox command client; requires VPN to be connected.
    func requestExtensionReload() {
        guard isConnected else { return }
        do {
            guard let client = OMLibboxNewStandaloneCommandClient() else { return }
            try client.serviceReload()
        } catch {
            NSLog("VPNController requestExtensionReload failed: %@", String(describing: error))
        }
    }

    /// Stop then start to apply updated protocol settings (excludeLocalNetworks, etc.).
    func reconnectToApplySettings() async {
        guard let profile else { return }
        let s = profile.status
        guard s == .connected || s == .connecting || s == .reasserting else { return }
        do {
            try await profile.stop()
            await profile.waitUntilDisconnected(timeoutSeconds: 20)
            try await profile.start()
        } catch {
            NSLog("VPNController reconnectToApplySettings failed: %@", String(describing: error))
        }
    }

    // MARK: - Manager Loading/Creation

    private func loadManager() async -> NETunnelProviderManager? {
        await withCheckedContinuation { cont in
            NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
                guard let self else {
                    cont.resume(returning: nil)
                    return
                }
                let byBundle = managers?.first(where: { mgr in
                    guard let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                    return proto.providerBundleIdentifier == Variant.extensionBundleIdentifier
                })
                if let byBundle {
                    cont.resume(returning: byBundle)
                    return
                }
                // Backward/compat: old code used a fixed localizedDescription.
                let byDesc = managers?.first(where: { $0.localizedDescription == self.descriptionFallback })
                cont.resume(returning: byDesc)
            }
        }
    }

    private func ensureManagerExists() async {
        let existing = await loadManager()
        if existing != nil { return }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
                guard let self else {
                    cont.resume()
                    return
                }
                if let managers, managers.contains(where: { $0.localizedDescription == self.descriptionFallback }) {
                    cont.resume()
                    return
                }

                let manager = NETunnelProviderManager()
                let proto = NETunnelProviderProtocol()
                proto.serverAddress = "MeshFlux Server"
                proto.providerBundleIdentifier = Variant.extensionBundleIdentifier

                var providerConfig: [String: Any] = [:]
                providerConfig["meshflux_config_nonce"] = self.configNonce
                providerConfig["meshflux_app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                proto.providerConfiguration = providerConfig

                // Settings are further applied by ExtensionProfile.start() using SharedPreferences.
                manager.protocolConfiguration = proto
                manager.localizedDescription = self.descriptionFallback
                manager.isEnabled = true
                manager.saveToPreferences { _ in
                    manager.loadFromPreferences { _ in
                        cont.resume()
                    }
                }
            }
        }
    }
}
