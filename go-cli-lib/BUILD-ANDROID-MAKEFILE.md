# Android AAR Build Guide

## 快速开始（推荐）

### Windows 用户 - 使用 BAT 脚本（最简单）

**双击运行或命令行执行：**
```cmd
cd D:\worker\openmesh-cli\go-cli-lib
.\build-android-verbose.bat
```

**特点：**
- ✅ 无需安装额外工具
- ✅ 显示详细编译日志
- ✅ 自动复制到 `openmesh-android/app/libs`
- ✅ Windows 原生支持

---

## 使用 Makefile（可选）

### 前提条件

需要安装 **make** 工具：

**Windows**: 安装以下任一环境：
- **Git Bash** - https://git-scm.com/
- **MSYS2** - https://www.msys2.org/ （需执行 `pacman -S make` 安装）
- **WSL** - Windows Subsystem for Linux

**macOS**: 已预装
```bash
xcode-select --install
```

**Linux**: 通常已预装

### 使用方法

```bash
# Git Bash / MSYS2 / WSL
cd /d/worker/openmesh-cli/go-cli-lib
make android
```

### Makefile 输出文件

编译成功后生成：
```
go-cli-lib/lib/android/
├── OpenMeshGo.aar              (~55 MB)
└── OpenMeshGo-sources.jar      (~55 KB)
```

Makefile 会自动复制到：
```
openmesh-android/app/libs/
├── OpenMeshGo.aar
└── OpenMeshGo-sources.jar
```

---

## 下一步

无论使用哪种方式编译，成功后都需要：

1. **打开 Android Studio**
2. **同步项目**: File → Sync Project with Gradle Files
3. **清理项目**: Build → Clean Project
4. **重新构建**: Build → Rebuild Project
5. **运行应用**: 部署到设备测试 VPN

---

## 编译产物位置

### BAT 脚本输出
```
go-cli-lib/lib/android/OpenMeshGo.aar
go-cli-lib/lib/android/OpenMeshGo-sources.jar
```

自动复制到：
```
openmesh-android/app/libs/OpenMeshGo.aar
openmesh-android/app/libs/OpenMeshGo-sources.jar
```

---

## 常见问题

### Q: BAT 脚本提示 "go 命令未找到"
**A**: 请先安装 Go：https://golang.org/dl/

### Q: 编译失败 - "clash api is not included"
**A**: 确保使用 `build-android-verbose.bat`，已包含正确的标签。

### Q: Android NDK 未找到
**A**: 通过 Android Studio 安装 NDK：
- Tools → SDK Manager → SDK Tools → NDK (Side by side)

### Q: gomobile 未找到
**A**: BAT 脚本会自动安装。或手动执行：
```bash
go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.11
gomobile init
```

### Q: 编译后仍然报错 "clash api not included"
**A**: 可能使用了旧的 AAR 缓存。在 Android Studio 中：
1. File → Invalidate Caches / Restart
2. Build → Clean Project
3. Build → Rebuild Project

---

## Makefile 相关（如果使用）

### Q: make 命令未找到（Windows）
**A**: 安装 Git Bash 或 MSYS2：
- Git Bash: https://git-scm.com/
- MSYS2: https://www.msys2.org/ （需执行 `pacman -S make`）

### Q: Makefile 的其他目标
```bash
make help          # 显示所有可用目标
make doctor        # 检查环境
make tools         # 安装 gomobile/gobind
make clean         # 清理构建产物
make android       # 构建 Android AAR
make ios           # 构建 iOS XCFramework
make macos         # 构建 macOS XCFramework
```

---

## Makefile 配置说明

当前 Makefile 已配置所有必要标签：
- ✅ `with_clash_api` - 启用 clash API（修复 VPN 启动失败）
- ✅ `with_gvisor` - gVisor TUN 实现
- ✅ `with_quic` - QUIC 协议支持
- ✅ `with_wireguard` - WireGuard 支持
- ✅ `with_utls` - TLS 指纹识别
- ✅ `with_conntrack` - 连接追踪
- ✅ 其他必要标签

---

**最后更新**: 2026-03-06  
**适用版本**: Android VPN with clash_api support
