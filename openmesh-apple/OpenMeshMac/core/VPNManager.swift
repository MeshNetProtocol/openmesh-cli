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
        alert.informativeText = "Error: \(error.localizedDescription)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func lastDisconnectError() -> Error? {
        guard let connection = manager?.connection else { return nil }
        return connection.value(forKey: "lastDisconnectError") as? NSError
    }
}
