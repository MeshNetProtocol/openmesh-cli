import SwiftUI
import Foundation
import Darwin
import VPNLibrary

@main
struct OpenMeshApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var router = AppRouter()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var vpnController = VPNController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootSwitchView()
                .environmentObject(router)
                .environmentObject(networkManager)
                .environmentObject(vpnController)
                .overlay {
                    AppHUDOverlay(hud: AppHUD.shared)
                }
                .onAppear {
                    AppMemoryLogger.shared.snapshot(tag: "app_appear")
                    AppMemoryLogger.shared.setPeriodicLoggingEnabled(scenePhase == .active)
                }
                .onChange(of: scenePhase) { phase in
                    NSLog("OpenMeshApp scenePhase changed: %@", String(describing: phase))
                    AppMemoryLogger.shared.snapshot(tag: "scenePhase=\(phase)")
                    AppMemoryLogger.shared.setPeriodicLoggingEnabled(phase == .active)
                    vpnController.setAppActive(phase == .active)
                }
        }
    }
}

private struct RootSwitchView: View {
    @EnvironmentObject private var router: AppRouter
    
    var body: some View {
        switch router.root {
        case .onboarding:
            NewAccountView()
        case .main:
            MainTabView()
        }
    }
}

private final class AppMemoryLogger {
    static let shared = AppMemoryLogger()

    private let queue = DispatchQueue(label: "meshflux.app.memory.logger")
    private var timer: DispatchSourceTimer?

    private init() {}

    func setPeriodicLoggingEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if enabled {
                guard self.timer == nil else { return }
                NSLog("AppMemoryLogger periodic timer enabled")
                let t = DispatchSource.makeTimerSource(queue: self.queue)
                t.schedule(deadline: .now() + 30, repeating: 30)
                t.setEventHandler { [weak self] in
                    self?.snapshot(tag: "periodic")
                }
                t.resume()
                self.timer = t
            } else {
                if self.timer != nil {
                    NSLog("AppMemoryLogger periodic timer disabled")
                }
                self.timer?.cancel()
                self.timer = nil
            }
        }
    }

    func snapshot(tag: String) {
        let footprint = currentPhysicalFootprintMB()
        if footprint > 0 {
            NSLog("AppMemoryLogger tag=%@ phys_footprint_mb=%.1f", tag, footprint)
        } else {
            NSLog("AppMemoryLogger tag=%@ phys_footprint_mb=unknown", tag)
        }
    }

    private func currentPhysicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }
}
