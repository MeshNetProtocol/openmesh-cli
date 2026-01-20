import Foundation
import OpenMeshGo
import Combine
import AppKit

class VPNManager: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
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
        // 定期检查VPN状态
        startStatusTimer()
    }
    
    private func startStatusTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateConnectionStatus()
        }
    }
    
    private func updateConnectionStatus() {
        let status = VPNManager.getStatus()
        DispatchQueue.main.async {
            self.isConnected = status
            self.isConnecting = false
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
        VPNManager.startVPN { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to start VPN: \(error)")
                    
                    self?.isConnecting = false
                    
                    // 弹出错误提示
                    let alert = NSAlert()
                    alert.messageText = "VPN Connection Failed"
                    alert.informativeText = "Error: \(error.localizedDescription)\n\nThis may be because TUN/TAP driver is not installed. Please install Tunnelblick or another TUN/TAP driver first."
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    func disconnectVPN() {
        VPNManager.stopVPN { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to stop VPN: \(error)")
                    
                    // 弹出错误提示
                    let alert = NSAlert()
                    alert.messageText = "VPN Disconnection Failed"
                    alert.informativeText = "Error: \(error.localizedDescription)"
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private static func startVPN(completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            var error: NSError?
            let result = OMOpenmeshStartVPN(&error)
            completion(error)
        }
    }
    
    private static func stopVPN(completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            var error: NSError?
            let result = OMOpenmeshStopVPN(&error)
            completion(error)
        }
    }
    
    private static func getStatus() -> Bool {
        var result: ObjCBool = false
        var error: NSError?
        let success = OMOpenmeshGetVPNStatus(&result, &error)
        if error != nil {
            print("Error getting VPN status: \(error!)")
            return false
        }
        return result.boolValue
    }
}