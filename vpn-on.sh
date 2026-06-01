#!/bin/bash
# 启动 sing-box 并开启 Mac WiFi 代理

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/singbox-client.json"
LOG="$SCRIPT_DIR/singbox.log"
PID_FILE="$SCRIPT_DIR/singbox.pid"

# 检查是否已在运行
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "sing-box 已在运行 (PID: $(cat "$PID_FILE"))"
else
  echo "启动 sing-box..."
  nohup sing-box run -c "$CONFIG" > "$LOG" 2>&1 &
  echo $! > "$PID_FILE"
  echo "sing-box 已启动 (PID: $!)"
  sleep 1
fi

# 开启 WiFi 代理
echo "配置 Mac WiFi 代理 -> 127.0.0.1:7890"
networksetup -setwebproxy "Wi-Fi" 127.0.0.1 7890
networksetup -setsecurewebproxy "Wi-Fi" 127.0.0.1 7890
networksetup -setsocksfirewallproxy "Wi-Fi" 127.0.0.1 7890
networksetup -setwebproxystate "Wi-Fi" on
networksetup -setsecurewebproxystate "Wi-Fi" on
networksetup -setsocksfirewallproxystate "Wi-Fi" on

echo "✅ VPN 已开启"
