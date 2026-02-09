import AppKit
import SwiftUI

@MainActor
final class ProviderInstallWindowManager {
    static let shared = ProviderInstallWindowManager()

    private var panel: NSPanel?

    func show(
        provider: TrafficProvider,
        installAction: (@Sendable (@Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)? = nil,
        onInstallingChange: @escaping (Bool) -> Void
    ) {
        let view = ProviderInstallWizard(
            provider: provider,
            installAction: installAction,
            onInstallingChange: onInstallingChange,
            onClose: { [weak self] in
                self?.close()
            }
        )

        if let panel {
            if let hosting = panel.contentViewController as? NSHostingController<AnyView> {
                hosting.rootView = AnyView(view)
            } else {
                panel.contentViewController = NSHostingController(rootView: AnyView(view))
            }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: AnyView(view))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "安装供应商"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        panel.contentViewController = hosting
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
