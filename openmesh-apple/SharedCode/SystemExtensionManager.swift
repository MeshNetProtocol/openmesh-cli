import Foundation
import SystemExtensions
import os.log
import Combine

@MainActor
class SystemExtensionManager: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let shared = SystemExtensionManager()
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SystemExtension")
    
    let extensionIdentifier = "com.meshnetprotocol.OpenMesh.macsys.vpn-extension"
    
    @Published var status: String = "Unknown"
    
    override private init() {
        super.init()
        self.checkStatus()
    }
    
    func checkStatus() {
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
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
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    // MARK: - OSSystemExtensionRequestDelegate
    
    func request(_ request: OSSystemExtensionRequest, willCompleteWithResult result: OSSystemExtensionRequest.Result) {
        logger.log("System extension request will complete with result: \(result.rawValue)")
        if result == .completed {
            DispatchQueue.main.async {
                self.status = "Installed"
            }
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        logger.log("System extension request finished with result: \(result.rawValue)")
        DispatchQueue.main.async {
            if result == .completed {
                self.status = "Activated successfully"
            } else {
                self.status = "Request finished with code: \(result.rawValue)"
            }
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("System extension request failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.status = "Error: \(error.localizedDescription)"
        }
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.log("System extension request needs user approval.")
        DispatchQueue.main.async {
            self.status = "Needs user approval. Check System Settings."
        }
    }
}