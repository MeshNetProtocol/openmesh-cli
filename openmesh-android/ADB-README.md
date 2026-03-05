# ADB 工具安装和使用指南

## ✅ ADB 已安装

ADB (Android Debug Bridge) 已经安装在你的系统中：

- **版本**: 1.0.41 (37.0.0-14910828)
- **安装路径**: `C:\Users\A\AppData\Local\Android\Sdk\platform-tools\adb.exe`

## 🔧 使用方法

### 方法 1：使用调试脚本（推荐）

在项目根目录运行：

```powershell
cd d:\worker\openmesh-cli\openmesh-android
.\adb-debug.ps1
```

这会自动：
1. 检查设备连接
2. 清除旧日志
3. 实时捕获 OpenMesh 相关的错误日志

### 方法 2：直接使用完整路径

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -s OpenMeshAndroid:*
```

### 方法 3：配置环境变量后使用

**注意**：环境变量配置后需要**重启 PowerShell**才能生效。

重启 PowerShell 后，可以直接使用：

```powershell
adb devices
adb logcat -s OpenMeshAndroid:*
```

## 📱 调试 Offline Import 闪退

### 步骤 1：连接设备/启动模拟器

确保你的 Android 设备已连接或模拟器已启动：

```powershell
.\adb-debug.ps1
# 或者
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
```

应该能看到类似输出：
```
List of devices attached
emulator-5554    device
```

### 步骤 2：开始监控日志

运行调试脚本：

```powershell
.\adb-debug.ps1
```

### 步骤 3：触发闪退

在手机上运行 App，点击 **Offline Import** 按钮

### 步骤 4：查看错误信息

日志中会显示类似：

```
E/OpenMeshAndroid(12345): 启动 OfflineImportActivity 失败：xxxxx
android.content.ActivityNotFoundException: ...
```

或者：

```
E/AndroidRuntime(12345): FATAL EXCEPTION: main
java.lang.RuntimeException: Unable to start activity ...
Caused by: android.view.InflateException: ...
```

## 🔍 常见错误类型

### 1. ActivityNotFoundException
```
原因：AndroidManifest.xml 中没有注册 OfflineImportActivity
解决：检查 <activity android:name=".OfflineImportActivity" /> 是否存在
```

### 2. InflateException / ResourcesNotFoundException
```
原因：布局文件中引用了不存在的资源（drawable/string/style）
解决：检查 activity_offline_import.xml 中所有 @drawable/ 和 @string/ 引用
```

### 3. ClassNotFoundException
```
原因：包名错误或类不存在
解决：检查完整的类名 com.meshnetprotocol.android.OfflineImportActivity
```

### 4. NullPointerException
```
原因：findViewById 返回 null
解决：检查布局文件中的 ID 是否与代码中一致
```

## 🛠️ 有用的 ADB 命令

```powershell
# 查看设备列表
adb devices

# 清除所有日志
adb logcat -c

# 只看错误日志
adb logcat *:E

# 只看 OpenMesh 相关日志
adb logcat -s OpenMeshAndroid:* MainActivity:* OfflineImportActivity:*

# 保存日志到文件
adb logcat -d > crash-log.txt

# 查看应用崩溃记录
adb shell dumpsys dropbox --print system_app_wtf
adb shell dumpsys dropbox --print system_app_crash

# 强制停止应用
adb shell am force-stop com.meshnetprotocol.android

# 清除应用数据
adb shell pm clear com.meshnetprotocol.android

# 重新启动 adb 服务器
adb kill-server
adb start-server
```

## 📝 下一步

现在你可以：

1. 运行 `.\adb-debug.ps1` 开始监控日志
2. 在手机上点击 Offline Import 按钮
3. 将日志中的错误信息发给我
4. 我会根据具体错误帮你修复问题

## ⚠️ 注意事项

1. **USB 调试**：确保手机已开启"开发者选项"和"USB 调试"
2. **驱动**：如果是真机，可能需要安装 USB 驱动
3. **模拟器**：推荐使用 Android Studio 自带的模拟器
4. **权限**：某些命令可能需要管理员权限

## 🆘 故障排查

### 找不到设备
```powershell
# 检查 USB 连接
adb devices

# 如果为空，尝试：
adb kill-server
adb start-server
adb devices
```

### 没有权限
右键点击 PowerShell → "以管理员身份运行"

### 日志太多看不清
```powershell
# 只看错误级别
adb logcat *:E

# 过滤特定标签
adb logcat -s OpenMeshAndroid:E
```

---

**准备就绪！** 🎉

现在运行 `.\adb-debug.ps1` 然后触发闪退，我就能看到具体的错误信息了！
