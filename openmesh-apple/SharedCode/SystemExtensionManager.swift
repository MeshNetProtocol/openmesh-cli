import Foundation
import SystemExtensions
@preconcurrency import NetworkExtension
import os.log
import Combine
#if canImport(AppKit)
import AppKit
#endif

@MainActor
class SystemExtensionManager: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let shared = SystemExtensionManager()
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SystemExtension")
    
    // Bundle identifier of the System Extension
    let extensionIdentifier = "com.meshnetprotocol.OpenMesh.macsys.vpn-extension"
    
    @Published var status: String = "Unknown"
    @Published var vpnStatus: NEVPNStatus = .invalid
    
    private var vpnManager: NETunnelProviderManager?
    
    override private init() {
        super.init()
        // Check current status on init
        self.checkStatus()
        self.loadVPNProfile()
    }
    
    func checkStatus() {
        // Just probing
        // Note: There isn't a direct API to silently check "is installed" without triggering a request logic in some contexts,
        // but checking VPN manager preference is a good proxy for "is configured".
    }
    
    func install() {
        logger.log("Requesting system extension installation.")
        status = "Requesting installation..."
        
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    func uninstall() {
        logger.log("Requesting system extension uninstallation.")
        status = "Requesting uninstallation..."
        
        // Remove VPN config first
        if let manager = vpnManager {
            manager.removeFromPreferences { error in
                if let error = error {
                    self.logger.error("Failed to remove VPN preference: \(error.localizedDescription)")
                }
            }
        }
        
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    // MARK: - VPN Configuration (NetworkExtension)
    
    func loadVPNProfile() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("Failed to load VPN preferences: \(error.localizedDescription)")
                    return
                }
                
                if let existingManager = managers?.first(where: {
                    // identifying our manager by bundle identifier or protocol type
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.extensionIdentifier
                }) {
                    self.vpnManager = existingManager
                    self.registerVPNStatusObserver()
                    self.status = "VPN Profile Loaded"
                }
            }
        }
    }
    
    func installVPNConfiguration() {
        self.status = "Configuring VPN service..."
        
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                let manager = managers?.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.extensionIdentifier
                }) ?? NETunnelProviderManager()
                
                let protocolConfiguration = NETunnelProviderProtocol()
                protocolConfiguration.providerBundleIdentifier = self.extensionIdentifier
                // 'serverAddress' is required but can be arbitrary for packet tunnels usually
                protocolConfiguration.serverAddress = "OpenMesh"
                protocolConfiguration.includeAllNetworks = true // Default to redirect all traffic or configure as needed
                
                manager.protocolConfiguration = protocolConfiguration
                manager.localizedDescription = "OpenMesh X"
                manager.isEnabled = true
                
                manager.saveToPreferences { error in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        
                        if let error = error {
                            self.logger.error("Failed to save VPN preference: \(error.localizedDescription)")
                            self.status = "VPN Configuration Failed: \(error.localizedDescription)"
                        } else {
                            self.logger.log("VPN preference saved successfully.")
                            self.status = "VPN Configured"
                            self.vpnManager = manager
                            
                            // We can try to load it again to be sure
                            self.loadVPNProfile()
                        }
                    }
                }
            }
        }
    }
    
    func startVPN() {
        guard let manager = vpnManager else {
            self.status = "No VPN Configuration found"
            return
        }
        
        do {
            try manager.connection.startVPNTunnel()
            self.status = "Starting VPN..."
        } catch {
            self.status = "Start VPN Failed: \(error.localizedDescription)"
            self.logger.error("Failed to start VPN: \(error.localizedDescription)")
        }
    }
    
    func stopVPN() {
        vpnManager?.connection.stopVPNTunnel()
    }
    
    private func registerVPNStatusObserver() {
        guard let connection = vpnManager?.connection else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(vpnStatusChanged), name: .NEVPNStatusDidChange, object: connection)
    }
    
    @objc private func vpnStatusChanged(notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }
        self.vpnStatus = connection.status
        self.status = "VPN Status: \(connection.status.description)"
    }
    
    // MARK: - OSSystemExtensionRequestDelegate
    
    func request(_ request: OSSystemExtensionRequest, willCompleteWithResult result: OSSystemExtensionRequest.Result) {
        logger.log("System extension request will complete with result: \(result.rawValue)")
        // Typically implies reboot might be needed for some types, but for Network Extensions usually ready immediately.
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        logger.log("System extension request finished with result: \(result.rawValue)")
        DispatchQueue.main.async {
            switch result {
            case .completed:
                self.status = "Extension Installed. Configuring VPN..."
                // Successfully installed the binary, now create the VPN Interface
                self.installVPNConfiguration()
            case .willCompleteAfterReboot:
                self.status = "Reboot required to finish installation."
            @unknown default:
                self.status = "Unknown result code: \(result.rawValue)"
            }
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("System extension request failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.status = "Extension Installation Failed: \(error.localizedDescription)"
        }
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.log("System extension request needs user approval.")
        DispatchQueue.main.async {
            self.status = "Needs user approval. Please check System Settings -> Privacy & Security."
            
            // Attempt to open System Settings to the relevant pane
            #if canImport(AppKit)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
                NSWorkspace.shared.open(url)
            }
            #endif
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        logger.log("System extension requesting replacement.")
        
        // sing-box logic comparison:
        // if existing.isAwaitingUserApproval { return .replace }
        // if versions match { return .cancel }
        
        // For simplicity during dev loops, we replace. In production, check versions.
        return .replace
    }
}

extension NEVPNStatus {
    var description: String {
        switch self {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reasserting: return "Reasserting"
        case .disconnecting: return "Disconnecting"
        @unknown default: return "Unknown"
        }
    }
}