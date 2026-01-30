//
//  AppHeartbeatWriter.swift
//  MeshFluxMac
//
//  当 VPN 已连接时，主 App 定期向 App Group 写入心跳文件；extension 读取该文件，
//  若连续 3 次未收到更新则认为主程序已退出（如被用户杀死），extension 主动关闭 VPN。
//

import Foundation
import VPNLibrary

/// 主程序存活时定期写入心跳；仅在 VPN 已连接时激活。
final class AppHeartbeatWriter {
    static let heartbeatInterval: TimeInterval = 8
    private var active = false
    private let queue = DispatchQueue(label: "com.meshflux.heartbeat.write", qos: .utility)

    func setActive(_ active: Bool) {
        queue.async { [weak self] in
            self?.setActiveOnQueue(active)
        }
    }

    private func setActiveOnQueue(_ active: Bool) {
        self.active = active
        if !active {
            removeHeartbeatFile()
            return
        }
        writeHeartbeatOnce()
        scheduleNext()
    }

    private func scheduleNext() {
        queue.asyncAfter(deadline: .now() + Self.heartbeatInterval) { [weak self] in
            guard let self, self.active else { return }
            self.writeHeartbeatOnce()
            self.scheduleNext()
        }
    }

    private func writeHeartbeatOnce() {
        let url = FilePath.appHeartbeatFile
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = String(format: "%.3f", Date().timeIntervalSince1970)
        try? ts.write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeHeartbeatFile() {
        try? FileManager.default.removeItem(at: FilePath.appHeartbeatFile)
    }
}
