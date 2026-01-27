import Foundation
import SystemExtensions
@preconcurrency import NetworkExtension
import os.log
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Extension installation state
enum ExtensionState: Equatable {
    case notInstalled
    case installing
    case waitingForApproval
    case approved
    case ready
    case failed(String)
}

@MainActor
class SystemExtensionManager: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let shared = SystemExtensionManager()
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SystemExtension")
    
    // Bundle identifier of the System Extension
    let extensionIdentifier = "com.meshnetprotocol.OpenMesh.macsys.vpn-extension"
    
    @Published var status: String = "Unknown"
    @Published var vpnStatus: NEVPNStatus = .invalid
    @Published var extensionState: ExtensionState = .notInstalled
    @Published var isFirstLaunch: Bool = true
    
    private var vpnManager: NETunnelProviderManager?
    private var approvalCheckTimer: Timer?
    
    override private init() {
        super.init()
        // Check if this is first launch
        self.isFirstLaunch = !UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
        
        // Always check status first. If we find an existing configuration, 
        // we can assume the extension is installed (coverage for reinstall).
        self.checkExtensionStatus()
    }
    
    /// Mark first launch as complete
    func markFirstLaunchComplete() {
        UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        isFirstLaunch = false
        // Refresh status
        checkExtensionStatus()
    }
    
    /// Check extension status by trying to load VPN profile
    func checkExtensionStatus() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("Failed to check extension status: \(error.localizedDescription)")
                    return
                }
                
                if let existingManager = managers?.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.extensionIdentifier
                }) {
                    self.vpnManager = existingManager
                    self.registerVPNStatusObserver()
                    self.extensionState = .ready
                    self.status = "Extension Ready"
                    self.stopApprovalCheckTimer()
                    
                    // If we found a valid config on first launch (e.g. reinstall), skip setup
                    if self.isFirstLaunch {
                        self.markFirstLaunchComplete()
                    }
                } else {
                    // No config found
                    if self.isFirstLaunch {
                        self.extensionState = .notInstalled
                    }
                }
            }
        }
    }
    
    /// Start periodic check for extension approval
    private func startApprovalCheckTimer() {
        stopApprovalCheckTimer()
        approvalCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkExtensionStatus()
            }
        }
    }
    
    /// Stop the approval check timer
    private func stopApprovalCheckTimer() {
        approvalCheckTimer?.invalidate()
        approvalCheckTimer = nil
    }
    
    /// Manually trigger a status check (for "Refresh" button)
    func refreshStatus() {
        status = "Checking status..."
        checkExtensionStatus()
    }
    
    /// Open system settings for extension approval
    func openSystemSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    
    func install() {
        logger.log("Requesting system extension installation.")
        status = "Requesting installation..."
        extensionState = .installing
        
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        
        // Attempt to open settings anyway after a short delay, as a fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.openSystemSettings()
        }
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
                protocolConfiguration.serverAddress = "MeshFlux"
                protocolConfiguration.includeAllNetworks = true // Default to redirect all traffic or configure as needed
                
                manager.protocolConfiguration = protocolConfiguration
                manager.localizedDescription = "MeshFlux X"
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
    
    var appGroupID: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.meshnetprotocol.OpenMesh"
        return "group.\(bundleID)"
    }
    
    // ... existing init ...
    
    // MARK: - Configuration & Rules
    
    private func openMeshSharedDirectory() throws -> URL {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "com.openmesh", code: 4001, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container: \(appGroupID)"])
        }
        
        let dir = groupURL.appendingPathComponent("MeshFlux", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Ensure App Group directory permissions allow System Extension (root) to read/write
    /// This is critical for sing-box compatible operation where basePath = App Group
    /// IMPORTANT: The root App Group directory MUST be 755 or 777 for root to access subdirs!
    private func ensureAppGroupPermissions() {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            logger.error("Cannot get App Group URL for permission fix")
            return
        }
        
        let fileManager = FileManager.default
        
        // CRITICAL: The App Group root directory is often created with 700 permissions.
        // Root cannot access subdirectories if the parent is 700 (no 'x' permission for others).
        // We MUST set at least 755 on all directories in the path.
        
        // Directories that System Extension needs access to (order matters - parent first)
        let dirsToFix = [
            groupURL,  // Base group container - MUST be accessible!
            groupURL.appendingPathComponent("Library", isDirectory: true),
            groupURL.appendingPathComponent("Library/Caches", isDirectory: true),
            groupURL.appendingPathComponent("Library/Caches/Working", isDirectory: true),
            groupURL.appendingPathComponent("MeshFlux", isDirectory: true)
        ]
        
        for dir in dirsToFix {
            // Create if not exists
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            
            // Set permissions to 0o777 (rwxrwxrwx) so root can read/write/traverse
            do {
                try fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: dir.path)
                logger.debug("Set permissions 777 on: \(dir.path)")
            } catch {
                logger.warning("Failed to set permissions on \(dir.path): \(error.localizedDescription)")
            }
        }
        
        // Also fix permissions on existing files in OpenMesh directory
        let openMeshDir = groupURL.appendingPathComponent("MeshFlux", isDirectory: true)
        if let files = try? fileManager.contentsOfDirectory(atPath: openMeshDir.path) {
            for file in files {
                let filePath = openMeshDir.appendingPathComponent(file).path
                try? fileManager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: filePath)
            }
        }
        
        // Verify the fix worked
        let rootPerms = (try? fileManager.attributesOfItem(atPath: groupURL.path))?[.posixPermissions] as? Int
        logger.info("App Group permissions fixed. Root dir permissions: \(String(format: "%o", rootPerms ?? 0))")
    }
    
    func prepareConfigurationFiles() {
        do {
            let dir = try openMeshSharedDirectory()
            let fileManager = FileManager.default
            
            // 1. Verify routing_rules.json (Managed by RoutingRulesStore)
            let rulesURL = dir.appendingPathComponent("routing_rules.json")
            if !fileManager.fileExists(atPath: rulesURL.path) {
                let msg = "CRITICAL: routing_rules.json MISSING in App Group directory: \(dir.path). syncBundledRulesIntoAppGroupIfNeeded must have failed."
                self.logger.error("\(msg)")
                // As requested: report error and crash
                fatalError(msg)
            }
            
            // 2. Verify singbox_config.json (Managed by SingboxConfigStore)
            let configURL = dir.appendingPathComponent("singbox_config.json")
            if !fileManager.fileExists(atPath: configURL.path) {
                self.logger.error("singbox_config.json is missing. VPN will fail to start until user saves a server.")
                // We DON'T crash here because the user might need to use the UI to Save it.
            }
            
            // 3. routing_mode.json is optional (Extension defaults to 'rule' if missing)
            
            // Log final state
            self.logger.log("Configuration files verification finished in App Group at: \(dir.path)")
            
            // List files for debugging
            if let files = try? fileManager.contentsOfDirectory(atPath: dir.path) {
                self.logger.log("App Group MeshFlux directory contains: \(files.joined(separator: ", "))")
            }
        } catch {
            self.logger.error("Failed to prepare configuration files: \(error.localizedDescription)")
        }
    }

    func startVPN() {
        self.status = "Starting VPN..."
        
        // 1. Fix App Group permissions so System Extension (root) can read/write
        ensureAppGroupPermissions()
        
        // 2. Prepare configuration files (Critical for extension startup)
        prepareConfigurationFiles()
        
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("Failed to load VPN preferences: \(error.localizedDescription)")
                    self.status = "VPN Load Failed: \(error.localizedDescription)"
                    return
                }
                
                let manager = managers?.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.extensionIdentifier
                }) ?? NETunnelProviderManager()
                
                // Configure protocol
                let protocolConfiguration = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
                protocolConfiguration.providerBundleIdentifier = self.extensionIdentifier
                protocolConfiguration.serverAddress = "MeshFlux"
                protocolConfiguration.includeAllNetworks = true
                
                // CRITICAL: For System Extensions, startVPNTunnel(options:) does NOT pass options to extension.
                // We must put all data in providerConfiguration instead.
                var providerConfig: [String: Any] = [:]
                providerConfig["openmesh_config_nonce"] = UUID().uuidString
                providerConfig["username"] = NSUserName()
                
                // Inject config content into providerConfiguration (not startVPNTunnel options)
                if let sharedDir = try? self.openMeshSharedDirectory() {
                    // 1. Config
                    let configURL = sharedDir.appendingPathComponent("singbox_config.json")
                    if let configData = try? Data(contentsOf: configURL),
                       let configStr = String(data: configData, encoding: .utf8) {
                        providerConfig["singbox_config_content"] = configStr
                        self.logger.info("VPN Config: Injecting singbox_config_content (len=\(configStr.count))")
                    }
                    
                    // 2. Rules
                    let rulesURL = sharedDir.appendingPathComponent("routing_rules.json")
                    if let rulesData = try? Data(contentsOf: rulesURL),
                       let rulesStr = String(data: rulesData, encoding: .utf8) {
                        providerConfig["routing_rules_content"] = rulesStr
                        self.logger.info("VPN Config: Injecting routing_rules_content (len=\(rulesStr.count))")
                    }
                }
                
                protocolConfiguration.providerConfiguration = providerConfig
                
                manager.protocolConfiguration = protocolConfiguration
                manager.localizedDescription = "MeshFlux X"
                manager.isEnabled = true
                
                // Save and Start
                manager.saveToPreferences { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.status = "VPN Save Failed: \(error.localizedDescription)"
                        }
                        return
                    }
                    
                    // Reload to ensure we have the latest state before starting
                    manager.loadFromPreferences { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.status = "VPN Reload Failed: \(error.localizedDescription)"
                                return
                            }
                            
                            do {
                                // For System Extensions, we pass username via startVPNTunnel options
                                // (like sing-box does). Config content is already in providerConfiguration.
                                let options: [String: NSObject] = [
                                    "username": NSUserName() as NSString
                                ]
                                
                                // DEBUG: Write launch info for inspection
                                if let sharedDir = try? self.openMeshSharedDirectory() {
                                    let provConfig = (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
                                    let debugInfo: [String: Any] = [
                                        "timestamp": ISO8601DateFormatter().string(from: Date()),
                                        "username": NSUserName(),
                                        "sharedDir": sharedDir.path,
                                        "singbox_config_content_len": (provConfig?["singbox_config_content"] as? String)?.count ?? 0,
                                        "routing_rules_content_len": (provConfig?["routing_rules_content"] as? String)?.count ?? 0,
                                        "providerConfiguration_keys": Array(provConfig?.keys ?? [String: Any]().keys)
                                    ]
                                    let debugURL = sharedDir.appendingPathComponent("vpn_launch_debug.json")
                                    if let debugData = try? JSONSerialization.data(withJSONObject: debugInfo, options: .prettyPrinted) {
                                        try? debugData.write(to: debugURL)
                                    }
                                }
                                
                                try manager.connection.startVPNTunnel(options: options)
                                self.status = "Connecting..."
                                self.vpnManager = manager // Update reference
                            } catch {
                                self.status = "Start Connection Failed: \(error.localizedDescription)"
                                self.logger.error("Failed to start VPN: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
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
            self.stopApprovalCheckTimer()
            switch result {
            case .completed:
                self.extensionState = .approved
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
            self.stopApprovalCheckTimer()
            self.extensionState = .failed(error.localizedDescription)
            self.status = "Extension Installation Failed: \(error.localizedDescription)"
        }
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.log("System extension request needs user approval.")
        DispatchQueue.main.async {
            self.extensionState = .waitingForApproval
            self.status = "Waiting for user approval..."
            
            // Start periodic check for approval
            self.startApprovalCheckTimer()
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
