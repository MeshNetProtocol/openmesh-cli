import AppKit
import SwiftUI

@MainActor
final class BootstrapFetchWindowManager: NSObject, NSWindowDelegate {
    static let shared = BootstrapFetchWindowManager()

    private weak var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show(
        onImportConfig: @escaping () -> Void,
        onInstallResolvedConfig: @escaping () -> Void
    ) {
        let root = BootstrapFetchWizardView(
            onImportConfig: onImportConfig,
            onInstallResolvedConfig: onInstallResolvedConfig,
            onClose: { [weak self] in self?.close() }
        )

        if let w = window, let hosting = hostingView {
            hosting.rootView = AnyView(root)
            w.minSize = NSSize(width: 760, height: 560)
            w.maxSize = NSSize(width: 1200, height: 900)
            NSApp.activate(ignoringOtherApps: true)
            w.level = .floating
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
            return
        }

        let size = NSSize(width: 860, height: 620)
        let hosting = NSHostingView(rootView: AnyView(root))
        self.hostingView = hosting

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hosting
        w.title = "获取可用配置"
        w.minSize = NSSize(width: 760, height: 560)
        w.maxSize = NSSize(width: 1200, height: 900)
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

    func close() {
        window?.close()
        window = nil
        hostingView = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if window === closing {
            window = nil
            hostingView = nil
        }
    }
}

