#!/bin/bash

cd "$(dirname "$0")"

./traffic-collector > logs/collector.log 2>&1 &

echo $! > traffic-collector.pid

echo "Traffic collector started (PID: $!)"
echo "Logs: logs/collector.log"
