#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/1.log"
STDERR_LOG="/var/tmp/OpenMesh.macsys/Library/Caches/stderr.log"

# Clear log file before starting
> "$LOG_FILE"

# Function to monitor stderr.log in background (waits for file to exist)
monitor_stderr() {
    # Wait for stderr.log to be created
    while [ ! -f "$STDERR_LOG" ]; do
        sleep 1
    done
    # Once file exists, tail it
    tail -f "$STDERR_LOG" 2>/dev/null | while IFS= read -r line; do
        echo "[Go stderr] $line" >> "$LOG_FILE"
    done
}

# Start monitoring stderr.log in background
monitor_stderr &
STDERR_PID=$!

# Trap to kill background process on exit
trap "kill $STDERR_PID 2>/dev/null; exit" EXIT INT TERM

# Monitor system logs
log stream --predicate 'eventMessage CONTAINS "MeshFlux"' --level debug --color always >> "$LOG_FILE" 2>&1
