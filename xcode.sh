#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${OPENMESH_VPN_LOG_FILE:-"$(pwd)/vpn_extension_macos.log"}"
PREDICATE_DEFAULT='process == "OpenMeshMac" OR process == "vpn_extension_macos" OR process == "nehelper" OR process == "nesessionmanager" OR process == "neagent" OR process == "pkd" OR process == "runningboardd" OR process == "amfid" OR process == "syspolicyd" OR process == "launchd" OR subsystem == "com.apple.networkextension" OR subsystem == "com.apple.NetworkExtension" OR subsystem == "com.apple.nesessionmanager" OR subsystem CONTAINS "PlugInKit" OR subsystem CONTAINS "runningboard"'
PREDICATE="${OPENMESH_LOG_PREDICATE:-$PREDICATE_DEFAULT}"
LEVEL="${OPENMESH_LOG_LEVEL:-debug}"

# Clear previous content each run.
: > "$LOG_FILE"
echo "Logging OpenMesh VPN related logs to: $LOG_FILE"
echo "Predicate: $PREDICATE"
echo "Level    : $LEVEL"
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "NOTE: Some NetworkExtension logs are only visible with sudo. If you see nothing, try: sudo $0"
fi

log stream --style compact --level "$LEVEL" --predicate "$PREDICATE" | tee -a "$LOG_FILE"
