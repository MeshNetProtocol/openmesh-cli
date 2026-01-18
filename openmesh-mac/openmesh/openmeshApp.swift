//
//  openmeshApp.swift
//  openmesh-mac
//
//  Created by wesley on 2026/1/18.
//

import SwiftUI

@main
struct openmeshApp: App {
    // 1. 使用 AppStorage 或状态来管理逻辑
        @State private var currentNumber = 0

        var body: some Scene {
            // 2. 使用 MenuBarExtra 代替 WindowGroup
            MenuBarExtra("My App", systemImage: "\(currentNumber).circle") {
                // 3. 这里编写点击菜单后显示的菜单项
                Button("增加数字") {
                    currentNumber += 1
                }
                
                Divider() // 分割线
                
                Button("退出应用") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q") // 快捷键 Cmd+Q
            }
        }
}
