#!/bin/bash

# 创建测试文件生成器

set -e

echo "生成测试文件..."

# 创建测试文件目录
mkdir -p /tmp/hysteria_test_files

# 生成不同大小的测试文件
dd if=/dev/urandom of=/tmp/hysteria_test_files/100kb.bin bs=1024 count=100 2>/dev/null
dd if=/dev/urandom of=/tmp/hysteria_test_files/256kb.bin bs=1024 count=256 2>/dev/null
dd if=/dev/urandom of=/tmp/hysteria_test_files/512kb.bin bs=1024 count=512 2>/dev/null

echo "测试文件已生成:"
ls -lh /tmp/hysteria_test_files/

# 启动简单的 HTTP 服务器
echo ""
echo "启动 HTTP 文件服务器在端口 8888..."
cd /tmp/hysteria_test_files
python3 -m http.server 8888 > /dev/null 2>&1 &
echo $! > /tmp/test_server.pid

echo "HTTP 服务器已启动 (PID: $(cat /tmp/test_server.pid))"
echo "测试文件可通过以下 URL 访问:"
echo "  - http://localhost:8888/100kb.bin"
echo "  - http://localhost:8888/256kb.bin"
echo "  - http://localhost:8888/512kb.bin"
