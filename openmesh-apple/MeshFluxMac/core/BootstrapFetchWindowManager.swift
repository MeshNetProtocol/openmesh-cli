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
            let fixed = NSSize(width: 620, height: 660)
            w.setContentSize(fixed)
            w.minSize = fixed
            w.maxSize = fixed
            NSApp.activate(ignoringOtherApps: true)
            w.level = .floating
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
            return
        }

        let size = NSSize(width: 620, height: 660)
        let hosting = NSHostingView(rootView: AnyView(root))
        self.hostingView = hosting

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.contentView = hosting
        w.title = "配置设置向导"
        w.minSize = size
        w.maxSize = size
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
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
