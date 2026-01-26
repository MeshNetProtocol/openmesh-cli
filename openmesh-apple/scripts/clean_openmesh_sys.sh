#!/usr/bin/env bash
set -euo pipefail

# OpenMesh.Sys 清理脚本
# 用于开发测试时清理系统扩展、VPN配置和App Group数据

echo "=== OpenMesh.Sys 清理脚本 ==="

# 配置
BUNDLE_ID="com.meshnetprotocol.OpenMesh.macsys"
EXTENSION_ID="com.meshnetprotocol.OpenMesh.macsys.vpn-extension"
TEAM_ID="2XYK8RBB6M"
APP_GROUP_ID="group.com.meshnetprotocol.OpenMesh.macsys"
VPN_NAME="OpenMesh X"

echo ""
echo "1. 停止 VPN 连接..."
scutil --nc stop "$VPN_NAME" 2>/dev/null || echo "   VPN 未运行或不存在"

echo ""
echo "2. 删除 VPN 配置..."
# 使用 networksetup 或直接操作 plist 比较复杂，这里提示手动操作
VPN_EXISTS=$(scutil --nc list 2>/dev/null | grep -c "$BUNDLE_ID" || true)
if [[ "$VPN_EXISTS" -gt 0 ]]; then
    echo "   检测到 VPN 配置，请手动删除："
    echo "   系统设置 → 网络 → 删除 '$VPN_NAME'"
    echo ""
    echo "   或者等待重启后自动清理"
else
    echo "   ✅ 无 VPN 配置需要清理"
fi

echo ""
echo "3. 请求卸载系统扩展..."
# 检查扩展是否存在
EXT_EXISTS=$(systemextensionsctl list 2>&1 | grep -c "$EXTENSION_ID" || true)
if [[ "$EXT_EXISTS" -gt 0 ]]; then
    echo "   检测到系统扩展已安装"
    echo "   尝试通过应用卸载..."
    
    # 如果应用还在运行，可以通过它来卸载
    APP_PATH="/Applications/MeshFlux X.app"
    if [[ -d "$APP_PATH" ]]; then
        echo "   应用存在于: $APP_PATH"
        echo "   建议："
        echo "   1. 打开应用并点击 Uninstall 按钮"
        echo "   2. 或者直接删除应用（重启后扩展会被清理）"
    fi
    
    # 显示当前状态
    echo ""
    echo "   当前系统扩展状态："
    systemextensionsctl list 2>&1 | grep "$EXTENSION_ID" || true
else
    echo "   ✅ 无系统扩展需要清理"
fi

echo ""
echo "4. 清理 App Group 数据..."
APP_GROUP_PATH="$HOME/Library/Group Containers/$APP_GROUP_ID"
if [[ -d "$APP_GROUP_PATH" ]]; then
    echo "   删除: $APP_GROUP_PATH"
    rm -rf "$APP_GROUP_PATH"
    echo "   ✅ App Group 数据已删除"
else
    echo "   ✅ App Group 目录不存在"
fi

echo ""
echo "5. 清理应用偏好设置..."
PREFS_PATH="$HOME/Library/Preferences/$BUNDLE_ID.plist"
if [[ -f "$PREFS_PATH" ]]; then
    echo "   删除: $PREFS_PATH"
    rm -f "$PREFS_PATH"
    echo "   ✅ 偏好设置已删除"
else
    echo "   ✅ 偏好设置不存在"
fi

echo ""
echo "6. 清理应用支持文件..."
APP_SUPPORT_PATH="$HOME/Library/Application Support/$BUNDLE_ID"
if [[ -d "$APP_SUPPORT_PATH" ]]; then
    echo "   删除: $APP_SUPPORT_PATH"
    rm -rf "$APP_SUPPORT_PATH"
    echo "   ✅ 应用支持文件已删除"
else
    echo "   ✅ 应用支持文件不存在"
fi

echo ""
echo "7. 删除应用本身..."
for app_path in "/Applications/MeshFlux X.app" "/Applications/OpenMesh.Sys.app"; do
    if [[ -d "$app_path" ]]; then
        echo "   删除: $app_path"
        rm -rf "$app_path"
        echo "   ✅ 应用已删除"
    fi
done

echo ""
echo "=== 清理完成 ==="
echo ""
echo "⚠️  重要提示："
echo "   - 如果系统扩展仍显示已安装，请重启 Mac 完成卸载"
echo "   - 重启后系统会自动清理孤立的扩展和 VPN 配置"
echo ""
echo "当前状态："
echo "---"
systemextensionsctl list 2>&1 | head -5
echo "---"
scutil --nc list 2>&1 | grep -i openmesh || echo "无 OpenMesh VPN 配置"
