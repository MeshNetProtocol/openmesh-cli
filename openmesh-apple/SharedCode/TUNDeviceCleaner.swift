import Foundation
import NetworkExtension

/// Utility for cleaning up TUN devices when VPN stops
/// Note: On macOS, TUN devices are managed by the system, but we can help ensure proper cleanup
class TUNDeviceCleaner {
    
    /// Clean up TUN devices after VPN stops
    /// This is called from the main app when VPN disconnects
    static func cleanupAfterVPNStop(manager: NETunnelProviderManager, completion: @escaping () -> Void) {
        // Wait a bit for the system to clean up TUN devices automatically
        // NetworkExtension framework handles TUN cleanup, but we give it time
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            // Check if VPN is fully disconnected
            let status = manager.connection.status
            if status == .disconnected || status == .invalid {
                // System should have cleaned up TUN devices automatically
                // We can log this for debugging
                NSLog("TUNDeviceCleaner: VPN stopped, system should have cleaned up TUN devices")
            }
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    /// Clean up any stale TUN devices (for debugging/development)
    /// Note: This is mainly for logging - actual cleanup is done by the system
    static func logTUNDeviceStatus() {
        // This is informational only - we can't actually delete TUN devices
        // They are managed by the system
        NSLog("TUNDeviceCleaner: TUN devices are managed by macOS NetworkExtension framework")
        NSLog("TUNDeviceCleaner: System automatically cleans up TUN devices when VPN stops")
    }
}
