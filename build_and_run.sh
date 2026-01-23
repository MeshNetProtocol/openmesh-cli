#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCHEME="OpenMesh.Sys"
APP_NAME="OpenMesh X.app"
DESTINATION="/Applications/$APP_NAME"
DERIVED_DATA_PATH="./DerivedData" # Local derived data for clean build
LOG_FILE="sys_extension_debug.log"

echo "=== 1. Building $SCHEME ==="
# Use a custom derived data path to easily locate the product
xcodebuild build \
  -scheme "$SCHEME" \
  -project "openmesh-apple/OpenMesh.xcodeproj" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -configuration Debug \
  -quiet

# Locate the built app
BUILT_APP=$(find "$DERIVED_DATA_PATH" -name "$APP_NAME" -type d | head -n 1)

if [ -z "$BUILT_APP" ]; then
  echo "Error: Could not find built app '$APP_NAME' in $DERIVED_DATA_PATH"
  exit 1
fi

echo "=== 2. Deploying to $DESTINATION ==="
# Kill existing process if running
echo "Killing existing instances..."
pkill -f "OpenMesh.Sys" || true
pkill -x "OpenMesh X" || true

# Remove old app
if [ -d "$DESTINATION" ]; then
  rm -rf "$DESTINATION"
fi

# Deployment: Use cp -R to preserve attributes
echo "Deploying to $DESTINATION..."
# Remove old app and copy new one cleanly
rm -rf "$DESTINATION"
cp -R "$BUILT_APP" "$DESTINATION"

# Remove quarantine attribute
xattr -rc "$DESTINATION"

echo "=== 3. Launching App ==="
open "$DESTINATION"

echo "=== 4. Streaming Logs (Press Ctrl+C to stop) ==="
# Filter logs for our processes and NetworkExtension subsystem
PREDICATE='process == "OpenMesh.Sys" OR process == "OpenMesh X" OR process == "sysextd" OR process == "amfid" OR process == "taskgated" OR subsystem == "com.meshnetprotocol.OpenMesh.macsys.vpn-extension" OR process == "nehelper" OR process == "nesessionmanager" OR subsystem == "com.apple.networkextension"'

echo "Logging to $LOG_FILE..."
: > "$LOG_FILE"

# Start log stream in background or foreground
log stream --style compact --level debug --predicate "$PREDICATE" | tee -a "$LOG_FILE"
