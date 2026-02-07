import Foundation
import OpenMeshGo
import VPNLibrary

actor LibboxBootstrap {
    static let shared = LibboxBootstrap()

    private var configured = false

    func ensureConfigured() async {
        if configured { return }
        configured = true

        let options = OMLibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.relativePath
        options.workingPath = FilePath.workingDirectory.relativePath
        options.tempPath = FilePath.cacheDirectory.relativePath

        var err: NSError?
        let ok = OMLibboxSetup(options, &err)
        if !ok || err != nil {
            NSLog("MeshFlux iOS OMLibboxSetup failed: %@", err?.localizedDescription ?? "unknown error")
        }

        OMLibboxSetMemoryLimit(true)
        let ignoreMemoryLimit = await SharedPreferences.ignoreMemoryLimit.get()
        OMLibboxSetMemoryLimit(!ignoreMemoryLimit)
        OMLibboxSetLocale(Locale.current.identifier)
    }
}
