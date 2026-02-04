#!/bin/bash
# 扁平化gomobile生成的framework结构，解决iOS 26.2.1符号链接问题

set -e

FRAMEWORK_DIR="$1"
if [ -z "$FRAMEWORK_DIR" ]; then
    echo "Usage: $0 <framework_directory>"
    exit 1
fi

echo "扁平化Framework结构: $FRAMEWORK_DIR"

# 备份原始结构
mv "$FRAMEWORK_DIR" "$FRAMEWORK_DIR.backup"

# 创建新的扁平化结构
mkdir -p "$FRAMEWORK_DIR"

# 复制实际文件（而不是符号链接）
cp -R "$FRAMEWORK_DIR.backup/Versions/A/"* "$FRAMEWORK_DIR/"

# 确保可执行文件在根目录
if [ -f "$FRAMEWORK_DIR.backup/Versions/A/$(basename "$FRAMEWORK_DIR" .framework)" ]; then
    cp "$FRAMEWORK_DIR.backup/Versions/A/$(basename "$FRAMEWORK_DIR" .framework)" "$FRAMEWORK_DIR/"
fi

# 验证结构
echo "扁平化后的结构:"
ls -la "$FRAMEWORK_DIR"

echo "Framework扁平化完成！"