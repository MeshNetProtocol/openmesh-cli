import Foundation
import Combine
import AppKit
import NetworkExtension

class VPNManager: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    
    private var cancellables = Set<AnyCancellable>()
    private var statusObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private let providerBundleIdentifier = "com.meshnetprotocol.OpenMesh.mac.vpn-extension"
    private let localizedDescription = "OpenMesh"
    private let appGroupID = "group.com.meshnetprotocol.OpenMesh"
    private let configNonce = UUID().uuidString
    private var manager: NETunnelProviderManager?
    private var didAttemptStart = false
    
    enum VPNError: LocalizedError {
        case startFailed(String)
        case stopFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .startFailed(let reason):
                return "Failed to start VPN: \(reason)"
            case .stopFailed(let reason):
                return "Failed to stop VPN: \(reason)"
            }
        }
    }
    
    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateConnectionStatus()
        }

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.disconnectVPN()
        }
        
        loadOrCreateManager { [weak self] _ in
            self?.updateConnectionStatus()
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }
    
    private func updateConnectionStatus() {
        guard let status = manager?.connection.status else {
            isConnected = false
            isConnecting = false
            return
        }
        
        isConnected = (status == .connected)
        isConnecting = (status == .connecting) || (status == .reasserting)

        if status == .disconnected, didAttemptStart {
            didAttemptStart = false
            if let error = lastDisconnectError() {
                presentError(title: "VPN Disconnected", error: error)
            }
        }
    }
    
    func toggleVPN() {
        if isConnected {
            disconnectVPN()
        } else {
            connectVPN()
        }
    }
    
    func connectVPN() {
        guard !isConnecting && !isConnected else { return }
        
        isConnecting = true
        didAttemptStart = true
        loadOrCreateManager { [weak self] result in
            guard let self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let manager):
                    manager.isEnabled = true
                    manager.saveToPreferences { error in
                        if let error {
                            self.presentError(title: "VPN Save Failed", error: error)
                            self.isConnecting = false
                            return
                        }
                        
                        manager.loadFromPreferences { loadError in
                            if let loadError {
                                self.presentError(title: "VPN Load Failed", error: loadError)
                                self.isConnecting = false
                                return
                            }
                            
                            do {
                                try manager.connection.startVPNTunnel()
                            } catch {
                                self.presentError(title: "VPN Connection Failed", error: error)
                                self.isConnecting = false
                            }
                        }
                    }
                case .failure(let error):
                    self.presentError(title: "VPN Setup Failed", error: error)
                    self.isConnecting = false
                }
            }
        }
    }
    
    func disconnectVPN() {
        guard let manager else { return }
        manager.connection.stopVPNTunnel()
    }
    
    private func loadOrCreateManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        if let manager {
            completion(.success(manager))
            return
        }
        
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error {
                completion(.failure(error))
                return
            }
            
            let existing = managers?.first(where: { manager in
                guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                return proto.providerBundleIdentifier == self?.providerBundleIdentifier
            })
            
            let manager = existing ?? NETunnelProviderManager()
            manager.localizedDescription = self?.localizedDescription
            
            let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self?.providerBundleIdentifier
            proto.serverAddress = "OpenMesh"

            // Force a preference update when the code signature / entitlements change across builds.
            // Otherwise `saveToPreferences` may no-op ("configuration unchanged"), and the system may
            // keep using an old stored signature, causing the provider launch to fail.
            var providerConfig = proto.providerConfiguration ?? [:]
            providerConfig["openmesh_config_nonce"] = self?.configNonce ?? UUID().uuidString
            providerConfig["openmesh_app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            proto.providerConfiguration = providerConfig

            manager.protocolConfiguration = proto
            manager.isEnabled = true
            
            self?.manager = manager
            completion(.success(manager))
        }
    }
    
    private func presentError(title: String, error: Error) {
        print("\(title): \(error)")
        let alert = NSAlert()
        alert.messageText = title
        if let nsError = error as NSError? {
            var lines: [String] = []
            lines.append(nsError.localizedDescription)
            lines.append("")
            lines.append("Domain: \(nsError.domain)")
            lines.append("Code: \(nsError.code)")
            if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
                lines.append("Reason: \(reason)")
            }
            if let suggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String, !suggestion.isEmpty {
                lines.append("Suggestion: \(suggestion)")
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                lines.append("")
                lines.append("Underlying: \(underlying.domain) (\(underlying.code)) \(underlying.localizedDescription)")
            }
            alert.informativeText = lines.joined(separator: "\n")
        } else {
            alert.informativeText = "Error: \(error.localizedDescription)"
        }
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func lastDisconnectError() -> Error? {
        guard let connection = manager?.connection else { return nil }
        return connection.value(forKey: "lastDisconnectError") as? NSError
    }

    // MARK: - Dynamic Routing Rules (App Group)

    /// Writes `routing_rules.json` into the App Group directory used by the VPN extension.
    /// Extension behavior: any match => outbound `proxy`, otherwise `direct`.
    func writeDynamicRoutingRulesJSON(ipCIDR: [String] = [], domain: [String] = [], domainSuffix: [String] = [], domainRegex: [String] = []) throws {
        let dir = try openMeshSharedDirectory()
        let url = dir.appendingPathComponent("routing_rules.json", isDirectory: false)
        let txtURL = dir.appendingPathComponent("routing_rules.txt", isDirectory: false)

        var obj: [String: Any] = ["version": 1]
        if !ipCIDR.isEmpty { obj["ip_cidr"] = ipCIDR }
        if !domain.isEmpty { obj["domain"] = domain }
        if !domainSuffix.isEmpty { obj["domain_suffix"] = domainSuffix }
        if !domainRegex.isEmpty { obj["domain_regex"] = domainRegex }

        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.removeItem(at: txtURL)
    }

    /// Writes `routing_rules.txt` into the App Group directory used by the VPN extension.
    func writeDynamicRoutingRulesText(_ content: String) throws {
        let dir = try openMeshSharedDirectory()
        let url = dir.appendingPathComponent("routing_rules.txt", isDirectory: false)
        let jsonURL = dir.appendingPathComponent("routing_rules.json", isDirectory: false)
        guard let data = content.data(using: .utf8) else {
            throw NSError(domain: "com.openmesh", code: 4002, userInfo: [NSLocalizedDescriptionKey: "Failed to encode routing rules as UTF-8"])
        }
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.removeItem(at: jsonURL)
    }

    /// Asks the running extension to reload its config (picks up changes from App Group files).
    func requestExtensionReload() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let message = ["action": "reload"]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do {
            try session.sendProviderMessage(data) { _ in }
        } catch {
            print("sendProviderMessage(reload) failed: \(error)")
        }
    }

    /// Pushes rules via `sendProviderMessage` (extension writes files + reloads). Requires VPN to be connected.
    func pushDynamicRoutingRules(format: String, content: String) {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let message: [String: Any] = ["action": "update_rules", "format": format, "content": content]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do {
            try session.sendProviderMessage(data) { _ in }
        } catch {
            print("sendProviderMessage(update_rules) failed: \(error)")
        }
    }

    private func openMeshSharedDirectory() throws -> URL {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "com.openmesh", code: 4001, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container: \(appGroupID)"])
        }
        let dir = groupURL.appendingPathComponent("OpenMesh", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
