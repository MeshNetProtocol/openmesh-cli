
import Foundation
import Darwin

final class FileSystemWatcher {
    private let url: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void

    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
    }

    func start() throws {
        guard source == nil else { return }
        let path = url.path
        fd = open(path, O_EVTONLY)
        if fd < 0 {
            throw NSError(domain: "com.meshflux", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Failed to open for watching: \(path)"])
        }

        let mask: DispatchSource.FileSystemEvent = [.write, .delete, .extend, .attrib, .link, .rename, .revoke]
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        src.setEventHandler { [weak self] in
            self?.onChange()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 {
                close(self.fd)
                self.fd = -1
            }
            self.source = nil
        }
        source = src
        src.resume()
    }

    func cancel() {
        source?.cancel()
    }
}
