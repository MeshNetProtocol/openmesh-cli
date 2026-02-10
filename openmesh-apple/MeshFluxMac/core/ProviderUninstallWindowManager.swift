import AppKit
import SwiftUI

final class ProviderUninstallWindowManager: NSObject, NSWindowDelegate {
    static let shared = ProviderUninstallWindowManager()

    private weak var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show(
        vpnController: VPNController,
        providerID: String,
        providerName: String,
        onFinished: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            let root = ProviderUninstallWizard(
                vpnController: vpnController,
                providerID: providerID,
                providerName: providerName,
                onFinished: { onFinished?() },
                onClose: { [weak self] in self?.close() }
            )
            if let w = self.window, let hostingView = self.hostingView {
                hostingView.rootView = AnyView(root)
                NSApp.activate(ignoringOtherApps: true)
                w.level = .floating
                w.makeKeyAndOrderFront(nil)
                w.orderFrontRegardless()
                return
            }

            let size = NSSize(width: 640, height: 520)
            let hosting = NSHostingView(rootView: AnyView(root))
            self.hostingView = hosting

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.contentView = hosting
            w.title = "卸载供应商"
            w.minSize = size
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.window = w

            w.center()
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
    }

    func close() {
        DispatchQueue.main.async {
            self.window?.close()
            self.window = nil
            self.hostingView = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let closing = notification.object as? NSWindow else { return }
            if self.window === closing {
                self.window = nil
                self.hostingView = nil
            }
        }
    }
}

