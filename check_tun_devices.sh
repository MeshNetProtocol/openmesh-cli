#!/bin/bash

echo "=== 检查所有 TUN 设备 ==="
ifconfig | grep -A 5 "^utun" || echo "没有找到 utun 设备"

echo -e "\n=== 检查路由表中的 TUN 设备 ==="
netstat -rn | grep -E "utun|172\.18\.0" || echo "路由表中没有找到 TUN 相关路由"

echo -e "\n=== 检查 VPN 相关进程 ==="
ps aux | grep -E "vpn|extension|MeshFlux" | grep -v grep || echo "没有找到 VPN 相关进程"

echo -e "\n=== 检查系统扩展状态 ==="
systemextensionsctl list | grep -i "mesh\|openmesh" || echo "没有找到相关系统扩展"

echo -e "\n=== 检查网络扩展配置 ==="
scutil --nc list | grep -i "mesh\|openmesh" || echo "没有找到相关网络配置"

echo -e "\n=== 检查所有网络接口（包括 TUN）==="
ifconfig -a | grep -E "^[a-z]|inet " | grep -B 1 -E "inet.*172\.18\.0|utun" || echo "没有找到 172.18.0.x 的接口"
