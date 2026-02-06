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
                NSLog("MeshFlux VPN extension: passing config to libbox. stderr.log: %@", stderrLogPath)
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
    /// Raw profile mode: do not rewrite route/dns by app mode.
    private func resolveConfigContent() throws -> String {
        let profileID = SharedPreferences.selectedProfileID.getBlocking()
        var content: String
        if profileID >= 0, let profile = try? ProfileManager.getBlocking(profileID) {
            do {
                content = try profile.read()
                NSLog("MeshFlux VPN extension using profile-driven config (id=%lld, name=%@)", profileID, profile.name)
            } catch {
                NSLog("MeshFlux VPN extension profile.read() failed: %@, trying default_profile", String(describing: error))
                content = try loadDefaultProfileContent()
            }
        } else {
            content = try loadDefaultProfileContent()
        }
        return applyRoutingModeToConfigContent(content, isGlobalMode: false)
    }

    private func loadDefaultProfileContent() throws -> String {
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

    private func pickPreferredURLTestGroupTag(timeoutSeconds: TimeInterval) throws -> String {
        let tags = try snapshotOutboundGroupTags(timeoutSeconds: timeoutSeconds)
        guard !tags.isEmpty else {
            throw NSError(domain: "com.meshflux", code: 5199, userInfo: [NSLocalizedDescriptionKey: "no outbound groups available"])
        }

        // Align with UI expectations: prefer "proxy" selector, then "auto".
        for preferred in ["proxy", "auto"] {
            if let match = tags.first(where: { $0.lowercased() == preferred }) {
                return match
            }
        }
        return tags[0]
    }

    private func snapshotOutboundGroupTags(timeoutSeconds: TimeInterval) throws -> [String] {
        guard boxService != nil else {
            throw NSError(domain: "com.meshflux", code: 5198, userInfo: [NSLocalizedDescriptionKey: "service not running"])
        }

        final class Snapshot: @unchecked Sendable {
            let lock = NSLock()
            var tags: [String] = []

            func update(_ tags: [String]) {
                lock.lock()
                self.tags = tags
                lock.unlock()
            }

            func read() -> [String] {
                lock.lock()
                defer { lock.unlock() }
                return tags
            }
        }

        final class Handler: NSObject, OMLibboxCommandClientHandlerProtocol {
            private let snapshot: Snapshot
            private let onUpdate: () -> Void

            init(snapshot: Snapshot, onUpdate: @escaping () -> Void) {
                self.snapshot = snapshot
                self.onUpdate = onUpdate
            }

            func connected() {}
            func disconnected(_ message: String?) { _ = message }
            func clearLogs() {}
            func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) { _ = messageList }
            func writeStatus(_ message: OMLibboxStatusMessage?) { _ = message }

            func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) {
                guard let groups else { return }
                var tags: [String] = []

                func stable(_ s: String) -> String {
                    String(decoding: Array(s.utf8), as: UTF8.self)
                }

                while groups.hasNext() {
                    guard let g = groups.next() else { break }
                    tags.append(stable(g.tag))
                }

                snapshot.update(tags)
                onUpdate()
            }

            func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) { _ = modeList; _ = currentMode }
            func updateClashMode(_ newMode: String?) { _ = newMode }
            func write(_ message: OMLibboxConnections?) { _ = message }
        }

        let snapshot = Snapshot()
        let updateSema = DispatchSemaphore(value: 0)
        let handler = Handler(snapshot: snapshot) { updateSema.signal() }

        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandGroup
        options.statusInterval = Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(handler, options) else {
            throw NSError(domain: "com.meshflux", code: 5197, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandClient returned nil"])
        }
        defer { _ = try? client.disconnect() }

        var connected = false
        for i in 0 ..< 20 {
            do {
                try client.connect()
                connected = true
                break
            } catch {
                Thread.sleep(forTimeInterval: 0.05 + Double(i) * 0.03)
            }
        }
        guard connected else {
            throw NSError(domain: "com.meshflux", code: 5196, userInfo: [NSLocalizedDescriptionKey: "command client connect failed"])
        }

        _ = updateSema.wait(timeout: .now() + timeoutSeconds)
        return snapshot.read()
    }

    private func urlTestAndSnapshotDelays(groupTag: String, timeoutSeconds: TimeInterval) throws -> [String: Int] {
        // urltest relies on the running libbox instance; require an active service.
        guard boxService != nil else {
            throw NSError(domain: "com.meshflux", code: 5201, userInfo: [NSLocalizedDescriptionKey: "service not running"])
        }

        final class Snapshot: @unchecked Sendable {
            let lock = NSLock()
            var maxItemTime: Double = 0
            var delays: [String: Int] = [:]

            func update(maxItemTime: Double, delays: [String: Int]) {
                lock.lock()
                self.maxItemTime = maxItemTime
                self.delays = delays
                lock.unlock()
            }

            func read() -> (maxItemTime: Double, delays: [String: Int]) {
                lock.lock()
                defer { lock.unlock() }
                return (maxItemTime, delays)
            }
        }

        final class Handler: NSObject, OMLibboxCommandClientHandlerProtocol {
            private let groupTagLower: String
            private let snapshot: Snapshot
            private let onUpdate: () -> Void

            init(groupTag: String, snapshot: Snapshot, onUpdate: @escaping () -> Void) {
                self.groupTagLower = groupTag.lowercased()
                self.snapshot = snapshot
                self.onUpdate = onUpdate
            }

            func connected() {}
            func disconnected(_ message: String?) { _ = message }
            func clearLogs() {}
            func writeLogs(_ messageList: OMLibboxStringIteratorProtocol?) { _ = messageList }
            func writeStatus(_ message: OMLibboxStatusMessage?) { _ = message }

            func writeGroups(_ groups: OMLibboxOutboundGroupIteratorProtocol?) {
                guard let groups else { return }
                var delays: [String: Int] = [:]
                var maxTime: Double = 0

                func stable(_ s: String) -> String {
                    String(decoding: Array(s.utf8), as: UTF8.self)
                }

                while groups.hasNext() {
                    guard let g = groups.next() else { break }
                    let tag = stable(g.tag)
                    if tag.lowercased() != groupTagLower { continue }
                    if let items = g.getItems() {
                        while items.hasNext() {
                            guard let it = items.next() else { break }
                            let itemTag = stable(it.tag)
                            let t = Double(it.urlTestTime)
                            if t > maxTime { maxTime = t }
                            let d = Int(it.urlTestDelay)
                            delays[itemTag] = d
                        }
                    }
                    break
                }

                snapshot.update(maxItemTime: maxTime, delays: delays)
                onUpdate()
            }

            func initializeClashMode(_ modeList: OMLibboxStringIteratorProtocol?, currentMode: String?) { _ = modeList; _ = currentMode }
            func updateClashMode(_ newMode: String?) { _ = newMode }
            func write(_ message: OMLibboxConnections?) { _ = message }
        }

        let snapshot = Snapshot()
        let updateSema = DispatchSemaphore(value: 0)
        let handler = Handler(groupTag: groupTag, snapshot: snapshot) { updateSema.signal() }

        let options = OMLibboxCommandClientOptions()
        options.command = OMLibboxCommandGroup
        options.statusInterval = Int64(NSEC_PER_SEC)

        guard let client = OMLibboxNewCommandClient(handler, options) else {
            throw NSError(domain: "com.meshflux", code: 5202, userInfo: [NSLocalizedDescriptionKey: "OMLibboxNewCommandClient returned nil"])
        }

        defer { _ = try? client.disconnect() }

        var connected = false
        for i in 0 ..< 20 {
            do {
                try client.connect()
                connected = true
                break
            } catch {
                Thread.sleep(forTimeInterval: 0.05 + Double(i) * 0.03)
            }
        }
        guard connected else {
            throw NSError(domain: "com.meshflux", code: 5203, userInfo: [NSLocalizedDescriptionKey: "command client connect failed"])
        }

        _ = updateSema.wait(timeout: .now() + 2.0)
        let (baselineTime, baselineDelays) = snapshot.read()

        try client.urlTest(groupTag)

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            _ = updateSema.wait(timeout: .now() + 0.6)
            let (t, d) = snapshot.read()
            if t > baselineTime { return d }
            if d != baselineDelays, d.values.contains(where: { $0 > 0 }) { return d }
        }

        throw NSError(domain: "com.meshflux", code: 5204, userInfo: [NSLocalizedDescriptionKey: "urltest timeout"])
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
            case "urltest":
                do {
                    let requested = dict["group"] as? String
                    let groupTag = (requested?.isEmpty == false) ? requested! : nil
                    let resolvedGroupTag: String
                    if let groupTag {
                        resolvedGroupTag = groupTag
                    } else {
                        resolvedGroupTag = try pickPreferredURLTestGroupTag(timeoutSeconds: 2.0)
                    }
                    let delays = try urlTestAndSnapshotDelays(groupTag: resolvedGroupTag, timeoutSeconds: 12)
                    let payload: [String: Any] = ["ok": true, "group": resolvedGroupTag, "delays": delays]
                    return try JSONSerialization.data(withJSONObject: payload, options: [])
                } catch {
                    let payload: [String: Any] = ["ok": false, "error": String(describing: error)]
                    return try? JSONSerialization.data(withJSONObject: payload, options: [])
                }
            default:
                return messageData
            }
        } catch {
            return messageData
        }
    }
}

final class PacketTunnelProvider: ExtensionProvider {}
