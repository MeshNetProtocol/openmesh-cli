//
//  VPNController.swift
//  MeshFluxMac
//
//  Phase 3: Wraps ExtensionProfile for start/stop and status; falls back to VPNManager when extension not loaded.
//

import Foundation
import NetworkExtension
import Combine
import VPNLibrary

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false

    private var extensionProfile: ExtensionProfile?
    private let legacyVPNManager = VPNManager()
    private let heartbeatWriter = AppHeartbeatWriter()
    private var useExtension: Bool { extensionProfile != nil }

    init() {
        Task {
            await loadExtensionProfile()
            updateStatus()
        }
        observeLegacyStatus()
    }

    func loadExtensionProfile() async {
        if let ep = try? await ExtensionProfile.load() {
            extensionProfile = ep
            ep.register()
            updateStatusFromExtension()
        } else {
            try? await ExtensionProfile.install()
            if let ep = try? await ExtensionProfile.load() {
                extensionProfile = ep
                ep.register()
                updateStatusFromExtension()
            }
        }
    }

    private func updateStatus() {
        if useExtension, let ep = extensionProfile {
            let s = ep.status
            isConnected = (s == .connected)
            isConnecting = (s == .connecting || s == .reasserting)
        } else {
            isConnected = legacyVPNManager.isConnected
            isConnecting = legacyVPNManager.isConnecting
        }
        heartbeatWriter.setActive(isConnected)
    }

    private func updateStatusFromExtension() {
        guard let ep = extensionProfile else { return }
        let s = ep.status
        isConnected = (s == .connected)
        isConnecting = (s == .connecting || s == .reasserting)
        heartbeatWriter.setActive(isConnected)
    }

    private func observeLegacyStatus() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let controller = self
            Task { @MainActor in
                controller.updateStatus()
            }
        }
    }

    func toggleVPN() {
        if useExtension {
            Task {
                await doExtensionToggle()
            }
        } else {
            legacyVPNManager.toggleVPN()
        }
    }

    private func doExtensionToggle() async {
        guard let ep = extensionProfile else { return }
        isConnecting = true
        do {
            if ep.status == .connected || ep.status == .connecting || ep.status == .reasserting {
                try await ep.stop()
            } else {
                try await ep.start()
            }
        } catch {
            NSLog("VPNController extension toggle failed: %@", String(describing: error))
        }
        updateStatusFromExtension()
    }
}
