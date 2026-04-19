#!/bin/bash

# Phase 4 启动脚本

set -e

echo "🚀 Starting Phase 4 file-based subscription POC..."

if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found, copying from .env.example"
    cp .env.example .env
    echo "📝 Please edit .env file with your configuration"
    exit 1
fi

cd auth-service

if ! command -v go &> /dev/null; then
    echo "❌ Go is not installed"
    exit 1
fi

echo "📦 Downloading dependencies..."
go mod download

echo "🔨 Building auth-service..."
go build -o auth-service

echo "✅ Starting file-based auth-service..."
./auth-service
