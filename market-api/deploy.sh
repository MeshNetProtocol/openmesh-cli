#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate to the project directory
cd "$SCRIPT_DIR"

echo "========================================"
echo "   Deploying OpenMesh Market API"
echo "========================================"

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "Error: npm is not installed"
    exit 1
fi

# Install dependencies
echo "📦 Installing dependencies..."
npm install

# Deploy to Cloudflare Workers
echo "🚀 Deploying to Cloudflare Workers..."
npm run deploy

echo "========================================"
echo "✅ Deployment complete!"
echo "========================================"
