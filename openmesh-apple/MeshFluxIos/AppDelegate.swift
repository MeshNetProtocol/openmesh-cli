import Foundation
import UIKit
import VPNLibrary
import OpenMeshGo

/// Align with sing-box SFI: initialize libbox once in UIApplicationDelegate (not in SwiftUI onAppear).
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let lock = NSLock()
    private static var didConfigureLibbox = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.configureLibboxIfNeeded()
        return true
    }

    private static func configureLibboxIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didConfigureLibbox else { return }
        didConfigureLibbox = true

        let options = OMLibboxSetupOptions()
        // Use relativePath to align with sing-box clients/apple/SFI and our extensions.
        options.basePath = FilePath.sharedDirectory.relativePath
        options.workingPath = FilePath.workingDirectory.relativePath
        options.tempPath = FilePath.cacheDirectory.relativePath

        var err: NSError?
        let ok = OMLibboxSetup(options, &err)
        if !ok || err != nil {
            NSLog("MeshFlux iOS OMLibboxSetup failed: %@", err?.localizedDescription ?? "unknown error")
        }

        OMLibboxSetLocale(Locale.current.identifier)
    }
}

