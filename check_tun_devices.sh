#!/bin/bash

echo "=== 检查 TUN 设备残留 ==="
echo ""

echo "1. 检查网络接口 (utun/tun):"
ifconfig 2>/dev/null | grep -E "utun|^tun" || echo "  未找到 TUN 设备或权限不足"
echo ""

echo "2. 检查路由表中的 172.18.x.x 路由:"
netstat -rn 2>/dev/null | grep -E "172\.18\." || echo "  未找到 172.18.x.x 路由或权限不足"
echo ""

echo "3. 检查 VPN 连接状态:"
scutil --nc list 2>/dev/null | grep -i "openmesh\|mesh" || echo "  未找到 OpenMesh VPN 连接"
echo ""

echo "4. 检查 OpenMesh 相关进程:"
ps aux 2>/dev/null | grep -E "OpenMesh|vpn-extension" | grep -v grep || echo "  未找到相关进程或权限不足"
echo ""

echo "5. 检查网络配置中的 VPN:"
system_profiler SPNetworkDataType 2>/dev/null | grep -A 10 -E "Type: VPN|OpenMesh" || echo "  未找到 VPN 配置或权限不足"
echo ""

echo "6. 检查默认路由:"
route -n get default 2>/dev/null || echo "  无法获取默认路由或权限不足"
echo ""

echo "7. 检查系统扩展状态:"
systemextensionsctl list 2>/dev/null | grep -i "openmesh\|mesh" || echo "  未找到相关系统扩展或权限不足"
echo ""

echo "8. 检查 NetworkExtension 进程:"
ps aux 2>/dev/null | grep -i "networkextension\|nesessionmanager" | grep -v grep || echo "  未找到 NetworkExtension 进程或权限不足"
echo ""

echo "=== 检查完成 ==="
echo ""
echo "提示: 如果看到权限不足的错误，请在终端中直接运行此脚本:"
echo "  bash $0"
