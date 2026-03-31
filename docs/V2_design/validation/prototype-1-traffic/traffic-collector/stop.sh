#!/bin/bash

cd "$(dirname "$0")"

if [ -f traffic-collector.pid ]; then
    PID=$(cat traffic-collector.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        rm traffic-collector.pid
        echo "Traffic collector stopped (PID: $PID)"
    else
        echo "Process $PID not running, removing stale PID file"
        rm traffic-collector.pid
    fi
else
    echo "No PID file found"
fi
