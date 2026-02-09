import AppKit
import SwiftUI

final class OfflineImportWindowManager {
    static let shared = OfflineImportWindowManager()

    private var window: NSWindow?
    private var hostingView: NSHostingView<OfflineImportView>?

    func show(onInstalled: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            if let w = self.window {
                NSApp.activate(ignoringOtherApps: true)
                w.level = .floating
                w.makeKeyAndOrderFront(nil)
                w.orderFrontRegardless()
                return
            }

            let view = OfflineImportView(
                onInstalled: {
                    onInstalled?()
                },
                onClose: { [weak self] in
                    self?.close()
                }
            )
            let hosting = NSHostingView(rootView: view)
            self.hostingView = hosting

            let size = NSSize(width: 680, height: 560)
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.contentView = hosting
            w.title = "离线导入安装"
            w.minSize = size
            w.isReleasedWhenClosed = false
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
}
