#!/bin/bash

# Phase 4 启动脚本

set -e

echo "🚀 Starting Phase 4 CDP Subscription Payment POC..."

# 检查环境
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found, copying from .env.example"
    cp .env.example .env
    echo "📝 Please edit .env file with your configuration"
    exit 1
fi

# 进入 auth-service 目录
cd auth-service

# 检查 Go 环境
if ! command -v go &> /dev/null; then
    echo "❌ Go is not installed"
    exit 1
fi

echo "📦 Downloading dependencies..."
go mod download

echo "🔨 Building auth-service..."
go build -o auth-service

echo "✅ Starting auth-service..."
./auth-service
