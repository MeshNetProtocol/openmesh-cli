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
    private var launchFinishObserver: NSObjectProtocol?

    init() {
        cfPrefsTrace("VPNController init")
        observeLegacyStatus()
        // 与 sing-box 一致：不在 init 中调用 ExtensionProfile.load()，延后到 applicationDidFinishLaunching 之后
        launchFinishObserver = NotificationCenter.default.addObserver(
            forName: .appLaunchDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            cfPrefsTrace("VPNController appLaunchDidFinish received, defer loadExtensionProfile to next run loop")
            DispatchQueue.main.async {
                cfPrefsTrace("VPNController deferred run loop: calling loadExtensionProfile")
                Task { @MainActor in
                    await self?.loadExtensionProfile()
                    self?.updateStatus()
                }
            }
        }
    }

    deinit {
        if let launchFinishObserver {
            NotificationCenter.default.removeObserver(launchFinishObserver)
        }
    }

    func loadExtensionProfile() async {
        cfPrefsTrace("VPNController loadExtensionProfile start (ExtensionProfile.load)")
        if let ep = try? await ExtensionProfile.load() {
            extensionProfile = ep
            ep.register()
            updateStatusFromExtension()
            cfPrefsTrace("VPNController loadExtensionProfile end (extension loaded)")
        } else {
            try? await ExtensionProfile.install()
            if let ep = try? await ExtensionProfile.load() {
                extensionProfile = ep
                ep.register()
                updateStatusFromExtension()
                cfPrefsTrace("VPNController loadExtensionProfile end (extension installed then loaded)")
            } else {
                cfPrefsTrace("VPNController loadExtensionProfile end (no extension, using legacy)")
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

    /// 通知已连接的 extension 重新加载配置（与 sing-box serviceReload 一致）；切换配置后调用。
    func requestExtensionReload() {
        guard isConnected else { return }
        legacyVPNManager.requestExtensionReload()
    }

    /// 若当前已连接，则先断开再连接，以应用最新的 protocol 设置（如 按规则分流/全局、本地网络）。供设置页切换模式时调用。
    /// 参考 SFM：stop 后需等待会话完全进入 disconnected，再 start，否则系统会忽略 start（session in state disconnecting）。
    func reconnectToApplySettings() async {
        guard let ep = extensionProfile else { return }
        let s = ep.status
        guard s == .connected || s == .connecting || s == .reasserting else { return }
        do {
            try await ep.stop()
            await ep.waitUntilDisconnected(timeoutSeconds: 20)
            try await ep.start()
        } catch {
            NSLog("VPNController reconnectToApplySettings failed: %@", String(describing: error))
        }
        updateStatusFromExtension()
    }
}
