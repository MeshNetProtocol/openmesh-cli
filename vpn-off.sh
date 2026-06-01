#!/bin/bash
# 停止 sing-box 并关闭 Mac WiFi 代理

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/singbox.pid"

# 停止 sing-box
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "停止 sing-box (PID: $(cat "$PID_FILE"))..."
  kill "$(cat "$PID_FILE")"
  rm -f "$PID_FILE"
  echo "sing-box 已停止"
else
  echo "sing-box 未在运行"
  rm -f "$PID_FILE"
fi

# 关闭 WiFi 代理
echo "关闭 Mac WiFi 代理..."
networksetup -setwebproxystate "Wi-Fi" off
networksetup -setsecurewebproxystate "Wi-Fi" off
networksetup -setsocksfirewallproxystate "Wi-Fi" off

echo "✅ VPN 已关闭"
