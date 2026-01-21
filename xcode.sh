#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${OPENMESH_VPN_LOG_FILE:-"$(pwd)/vpn_extension_macos.log"}"

# Clear previous content each run.
: > "$LOG_FILE"
echo "Logging vpn_extension_macos to: $LOG_FILE"

log stream --style compact --predicate 'process == "vpn_extension_macos"' | tee -a "$LOG_FILE"
