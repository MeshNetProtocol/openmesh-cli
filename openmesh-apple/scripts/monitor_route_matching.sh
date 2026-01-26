#!/bin/bash
# Monitor route matching logs for System Extension
# Usage: ./monitor_route_matching.sh

LOG_FILE="/var/tmp/OpenMesh.macsys/Library/Caches/route_match.log"
STDERR_LOG="/var/tmp/OpenMesh.macsys/Library/Caches/stderr.log"

echo "=== Monitoring OpenMesh System Extension Route Matching ==="
echo "Route match log: $LOG_FILE"
echo "Stderr log: $STDERR_LOG"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Monitor both files
tail -f "$LOG_FILE" "$STDERR_LOG" 2>/dev/null | grep -iE "route|domain|match|x\.com|twimg|facebook|outbound|proxy|direct" --color=always
