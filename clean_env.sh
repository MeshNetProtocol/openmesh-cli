# 0) 退出 OpenMeshMac、关闭 Xcode（避免文件占用）
osascript -e 'tell application "OpenMeshMac" to quit' 2>/dev/null || true
osascript -e 'tell application "Xcode" to quit' 2>/dev/null || true

# 1) 卸载任何挂载的 OpenMeshMac.dmg（如果有）
hdiutil info | rg -n "OpenMeshMac|openmesh" || true
# 如果上面看到 /Volumes/OpenMeshMac 之类：
# sudo hdiutil detach "/Volumes/OpenMeshMac" || true

# 2) 列出你机器上所有 OpenMeshMac.app（重点：/Volumes、/tmp、~/.Trash、Downloads、/Applications）
mdfind "kMDItemCFBundleIdentifier == 'com.meshnetprotocol.OpenMesh.mac'" 2>/dev/null || true
mdfind "kMDItemCFBundleIdentifier == 'com.meshnetprotocol.OpenMesh.mac.dev'" 2>/dev/null || true
find /Applications "$HOME/Applications" "$HOME/Downloads" "$HOME/.Trash" /private/tmp /Volumes \
  -maxdepth 5 -type d -name "OpenMeshMac.app" -print 2>/dev/null || true

# 3) 真的删除这些 OpenMeshMac.app（把你确认要删的路径逐个 rm 掉）
sudo rm -rf "/Applications/OpenMeshMac.app"
sudo rm -rf "/Volumes/OpenMeshMac/OpenMeshMac.app"
rm -rf "$HOME/.Trash/OpenMeshMac.app"* "$HOME/Downloads/OpenMeshMac.app"* 2>/dev/null || true
rm -rf /private/tmp/*OpenMeshMac* 2>/dev/null || true

# 4) 清理 Xcode DerivedData（你用的自定义路径 + 默认路径）
rm -rf "$HOME/xcodedata/Derived Data/OpenMesh-"* 2>/dev/null || true
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/OpenMesh-"* 2>/dev/null || true

# 5) 清 PlugInKit / RunningBoard 缓存（会影响 ExtensionKit service 映射）
rm -rf "$HOME/Library/Caches/com.apple.pluginkit/"* 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.apple.runningboard/"* 2>/dev/null || true

# 6) 重建 LaunchServices 数据库（清掉旧的 app/appex 注册记录）
LSR="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSR" -kill -r -domain local -domain system -domain user || true
pkill -u "$USER" lsd 2>/dev/null || true

# 7) 重启与 NetworkExtension/PlugInKit 相关的系统进程（需要 sudo）
sudo killall pkd 2>/dev/null || true
sudo killall neagent 2>/dev/null || true
sudo killall nesessionmanager 2>/dev/null || true

# 8) （可选，彻底清“应用自身数据”）删 sandbox 容器 + app group 数据
rm -rf "$HOME/Library/Containers/com.meshnetprotocol.OpenMesh.mac"* 2>/dev/null || true
rm -rf "$HOME/Library/Group Containers/group.com.meshnetprotocol.OpenMesh" 2>/dev/null || true
rm -f "$HOME/Library/Preferences/com.meshnetprotocol.OpenMesh.mac.plist" 2>/dev/null || true
