//
//  CFPrefsTrace.swift
//  MeshFluxMac
//
//  Optional debug trace for CFPrefs/sandbox (only in Debug builds).
//

import Foundation

#if DEBUG
private let _lock = NSLock()
private var _counter: Int = 0
#endif

/// In Debug: logs [CFPrefsTrace] with a sequential number. In Release: no-op.
func cfPrefsTrace(_ label: String) {
    #if DEBUG
    _lock.lock()
    let n = _counter
    _counter += 1
    _lock.unlock()
    NSLog("[CFPrefsTrace] %d %@", n, label)
    #endif
}
