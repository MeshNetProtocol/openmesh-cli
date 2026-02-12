import AppKit
import SwiftUI

@MainActor
final class ProviderInstallWindowManager: NSObject, NSWindowDelegate {
    static let shared = ProviderInstallWindowManager()

    private weak var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show(
        provider: TrafficProvider,
        installAction: (@Sendable (@escaping @Sendable (MarketService.InstallProgress) -> Void) async throws -> Void)? = nil,
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

        if let w = window, let hosting = hostingView {
            NSLog("ProviderInstallWindowManager: reuse existing install window")
            hosting.rootView = AnyView(view)
            w.minSize = NSSize(width: 720, height: 640)
            w.maxSize = NSSize(width: 1400, height: 640)
            if abs(w.frame.height - 640) > 0.5 {
                var frame = w.frame
                frame.size.height = 640
                w.setFrame(frame, display: true, animate: false)
            }
            NSApp.activate(ignoringOtherApps: true)
            w.level = .floating
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
            return
        }

        let size = NSSize(width: 880, height: 640)
        let hosting = NSHostingView(rootView: AnyView(view))
        self.hostingView = hosting

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hosting
        w.title = "安装供应商"
        w.minSize = NSSize(width: 720, height: 640)
        w.maxSize = NSSize(width: 1400, height: 640)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.window = w

        NSLog(
            "ProviderInstallWindowManager: created install window size=%@ minSize=%@ provider=%@",
            NSStringFromSize(size),
            NSStringFromSize(w.minSize),
            provider.id
        )
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    func close() {
        NSLog("ProviderInstallWindowManager: close requested")
        window?.close()
        window = nil
        hostingView = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if window === closing {
            NSLog("ProviderInstallWindowManager: windowWillClose")
            window = nil
            hostingView = nil
        }
    }
}
