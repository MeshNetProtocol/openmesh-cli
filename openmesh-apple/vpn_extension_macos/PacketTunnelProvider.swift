//
//  PacketTunnelProvider.swift
//  vpn_extension
//
//  Created by wesley on 2026/1/18.
//

import NetworkExtension
import OpenMeshGo
import Foundation
import VPNLibrary

// Match sing-box structure: PacketTunnelProvider is a thin subclass; logic lives in ExtensionProvider.
class ExtensionProvider: NEPacketTunnelProvider {
    private var commandServer: OMLibboxCommandServer?
    private var boxService: OMLibboxBoxService?
    private var platformInterface: OpenMeshLibboxPlatformInterface?
    private var baseDirURL: URL?
    private var cacheDirURL: URL?

    private let serviceQueue = DispatchQueue(label: "com.meshflux.vpn.service", qos: .userInitiated)
    private var pendingReload: DispatchWorkItem?
    /// 主程序心跳检测：若连续 3 次（约 30s）未读到更新，认为主程序已退出，主动关闭 VPN。
    private var heartbeatCheckWorkItem: DispatchWorkItem?
    private var heartbeatMissCount: Int = 0
    private static let heartbeatCheckInterval: TimeInterval = 10
    private static let heartbeatMaxAge: TimeInterval = 30
    private static let heartbeatMissesBeforeStop = 3

    private func prepareBaseDirectories(fileManager: FileManager) throws -> (baseDirURL: URL, basePath: String, workingPath: String, tempPath: String) {
        // Align with VPNLibrary/FilePath: use App Group as the shared root.
        guard let sharedDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName) else {
            throw NSError(domain: "com.meshflux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container. Check Signing & Capabilities (App Groups) for both the app and the extension."])
        }
        let baseDirURL = sharedDir
        let cacheDirURL = FilePath.cacheDirectory
        let workingDirURL = FilePath.workingDirectory
        let sharedDataDirURL = baseDirURL.appendingPathComponent("MeshFlux", isDirectory: true)

        // Keep the UNIX socket path within Darwin's `sockaddr_un.sun_path` limit (~104 bytes incl NUL).
        let commandSocketPath = baseDirURL.appendingPathComponent("command.sock", isDirectory: false).path
        let socketBytes = commandSocketPath.utf8.count
        if socketBytes > 103 {
            throw NSError(domain: "com.meshflux", code: 2, userInfo: [NSLocalizedDescriptionKey: "command.sock path too long (\(socketBytes) bytes): \(commandSocketPath)"])
        }

        try fileManager.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingDirURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sharedDataDirURL, withIntermediateDirectories: true)

        cleanupStaleCommandSocket(in: baseDirURL, fileManager: fileManager)
        self.cacheDirURL = cacheDirURL
        // Use relativePath to align with sing-box ExtensionProvider (SFM); on macOS App Group URL both are typically the same.
        return (
            baseDirURL: baseDirURL,
            basePath: baseDirURL.relativePath,
            workingPath: workingDirURL.relativePath,
            tempPath: cacheDirURL.relativePath
        )
    }

    private func cleanupStaleCommandSocket(in baseDirURL: URL, fileManager: FileManager) {
        let commandSocketURL = baseDirURL.appendingPathComponent("command.sock", isDirectory: false)
        if fileManager.fileExists(atPath: commandSocketURL.path) {
            try? fileManager.removeItem(at: commandSocketURL)
        }
    }

    override func startTunnel(options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("MeshFlux VPN extension startTunnel begin")

        // Keep the provider method fast/non-blocking: run the blocking libbox startup on a background queue.
        serviceQueue.async {
            var err: NSError?
            do {
                let fileManager = FileManager.default
                let prepared = try self.prepareBaseDirectories(fileManager: fileManager)
                let baseDirURL = prepared.baseDirURL
                let basePath = prepared.basePath
                let workingPath = prepared.workingPath
                let tempPath = prepared.tempPath

                self.baseDirURL = baseDirURL
                NSLog("MeshFlux VPN extension baseDirURL=%@", baseDirURL.path)

                let setup = OMLibboxSetupOptions()
                setup.basePath = basePath
                setup.workingPath = workingPath
                setup.tempPath = tempPath
                guard OMLibboxSetup(setup, &err) else {
                    throw err ?? NSError(domain: "com.meshflux", code: 2, userInfo: [NSLocalizedDescriptionKey: "OMLibboxSetup failed"])
                }

                // Capture Go/libbox stderr to a file inside the App Group cache directory (helps debugging panics).
                let stderrLogPath = (baseDirURL
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Caches", isDirectory: true)
                    .appendingPathComponent("stderr.log", isDirectory: false)).path
                _ = OMLibboxRedirectStderr(stderrLogPath, &err)
                err = nil

                let platform = OpenMeshLibboxPlatformInterface(self)
                let server = OMLibboxNewCommandServer(platform, 2000)
                guard let server else {
                    throw NSError(domain: "com.meshflux", code: 3, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandServer returned nil"])
                }

                self.platformInterface = platform
                self.commandServer = server

                // Align with sing-box ExtensionProvider: server.start() first, then NewService → service.start() → setService(service).
                try server.start()
                NSLog("MeshFlux VPN extension command server started")
                let configContent = try self.resolveConfigContent()
                var serviceErr: NSError?
                guard let boxService = OMLibboxNewService(configContent, platform, &serviceErr) else {
                    throw serviceErr ?? NSError(domain: "com.meshflux", code: 4, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewService failed"])
                }
                try boxService.start()
                NSLog("MeshFlux VPN extension box service started")
                server.setService(boxService)
                self.boxService = boxService

                self.startHeartbeatCheck()
                NSLog("MeshFlux VPN extension startTunnel completionHandler(nil)")
                completionHandler(nil)
            } catch {
                NSLog("MeshFlux VPN extension startTunnel failed: %@", String(describing: error))
                completionHandler(error)
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Explicitly clear tunnel network settings first so the system releases our routes/primary
        // immediately. Otherwise the session can leave stale state and cause "not primary for IPv4/IPv6"
        // when starting another VPN (e.g. system-level MeshFlux X) later.
        setTunnelNetworkSettings(nil) { [weak self] _ in
            self?.serviceQueue.async {
                guard let self = self else { completionHandler(); return }
                self.pendingReload?.cancel()
                self.pendingReload = nil
                self.heartbeatCheckWorkItem?.cancel()
                self.heartbeatCheckWorkItem = nil

                try? self.boxService?.close()
                try? self.commandServer?.close()
                self.boxService = nil
                self.commandServer = nil
                self.platformInterface?.reset()
                self.platformInterface = nil
                if let baseDirURL = self.baseDirURL {
                    self.cleanupStaleCommandSocket(in: baseDirURL, fileManager: .default)
                }
                completionHandler()
            }
        }
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        serviceQueue.async {
            let response = self.handleAppMessage0(messageData)
            completionHandler?(response)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Align with sing-box: pause box service when system sleeps.
        boxService?.pause()
        completionHandler()
    }

    override func wake() {
        // Align with sing-box: resume box service when system wakes.
        boxService?.wake()
    }

    // MARK: - Config resolution (profile-driven only)

    /// Resolves config: selectedProfileID → Profile → profile.read(); else bundled default_profile.json; else 报错（不再使用旧回退路径）。
    private func resolveConfigContent() throws -> String {
        let profileID = SharedPreferences.selectedProfileID.getBlocking()
        if profileID >= 0, let profile = try? ProfileManager.getBlocking(profileID) {
            do {
                let content = try profile.read()
                NSLog("MeshFlux VPN extension using profile-driven config (id=%lld, name=%@)", profileID, profile.name)
                return content
            } catch {
                NSLog("MeshFlux VPN extension profile.read() failed: %@, trying default_profile", String(describing: error))
            }
        }
        // No profile: use bundled default_profile.json only.
        let defaultProfileURL = Bundle.main.url(forResource: "default_profile", withExtension: "json")
            ?? Bundle.main.url(forResource: "default_profile", withExtension: "json", subdirectory: "MeshFluxMac")
        if let url = defaultProfileURL,
           let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8), !content.isEmpty {
            NSLog("MeshFlux VPN extension using bundled default_profile.json")
            return content
        }
        throw NSError(domain: "com.meshflux", code: 3010, userInfo: [NSLocalizedDescriptionKey: "No profile selected and no default profile. Please create or select a profile in the app, then reconnect VPN."])
    }

    private func scheduleReload(reason: String) {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadService(reason: reason)
        }
        pendingReload = work
        serviceQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reloadService(reason: String) {
        guard let commandServer, let platform = platformInterface else { return }
        do {
            NSLog("MeshFlux VPN extension reloadService(%@) begin", reason)
            // Align with sing-box / macx: close old service and setService(nil) first, then create+start new service.
            try? boxService?.close()
            commandServer.setService(nil)
            boxService = nil
            let content = try resolveConfigContent()
            var serviceErr: NSError?
            guard let newService = OMLibboxNewService(content, platform, &serviceErr) else {
                NSLog("MeshFlux VPN extension reloadService(%@) failed: %@", reason, String(describing: serviceErr))
                return
            }
            try newService.start()
            commandServer.setService(newService)
            boxService = newService
            NSLog("MeshFlux VPN extension reloadService(%@) done", reason)
        } catch {
            NSLog("MeshFlux VPN extension reloadService(%@) failed: %@", reason, String(describing: error))
        }
    }

    private func startHeartbeatCheck() {
        heartbeatCheckWorkItem?.cancel()
        heartbeatMissCount = 0
        scheduleHeartbeatCheck()
    }

    private func scheduleHeartbeatCheck() {
        let work = DispatchWorkItem { [weak self] in
            self?.performHeartbeatCheck()
        }
        heartbeatCheckWorkItem = work
        serviceQueue.asyncAfter(deadline: .now() + Self.heartbeatCheckInterval, execute: work)
    }

    private func performHeartbeatCheck() {
        heartbeatCheckWorkItem = nil
        let url = FilePath.appHeartbeatFile
        let now = Date().timeIntervalSince1970
        var missed = true
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let ts = Double(line), (now - ts) <= Self.heartbeatMaxAge {
            missed = false
        }
        if missed {
            heartbeatMissCount += 1
            if heartbeatMissCount >= Self.heartbeatMissesBeforeStop {
                NSLog("MeshFlux VPN extension: main app heartbeat missed %d times, stopping tunnel", heartbeatMissCount)
                cancelTunnelWithError(nil)
                return
            }
        } else {
            heartbeatMissCount = 0
        }
        scheduleHeartbeatCheck()
    }

    private func handleAppMessage0(_ messageData: Data) -> Data? {
        // Expected JSON:
        // {"action":"reload"}
        // {"action":"update_rules","format":"json"|"txt","content":"..."}
        do {
            let obj = try JSONSerialization.jsonObject(with: messageData, options: [.fragmentsAllowed])
            guard let dict = obj as? [String: Any], let action = dict["action"] as? String else {
                return messageData
            }

            switch action {
            case "reload":
                scheduleReload(reason: "app")
                return #"{"ok":true}"#.data(using: .utf8)
            default:
                return messageData
            }
        } catch {
            return messageData
        }
    }
}

final class PacketTunnelProvider: ExtensionProvider {}
