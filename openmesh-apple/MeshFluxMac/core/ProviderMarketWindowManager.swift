import AppKit
import SwiftUI

final class ProviderMarketWindowManager: NSObject, NSWindowDelegate {
    static let shared = ProviderMarketWindowManager()

    private weak var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show(vpnController: VPNController) {
        DispatchQueue.main.async {
            let root = ProviderMarketManagerView(
                vpnController: vpnController,
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

            let size = NSSize(width: 860, height: 640)
            let hosting = NSHostingView(rootView: AnyView(root))
            self.hostingView = hosting

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.contentView = hosting
            w.title = "供应商市场"
            w.minSize = NSSize(width: 760, height: 540)
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

