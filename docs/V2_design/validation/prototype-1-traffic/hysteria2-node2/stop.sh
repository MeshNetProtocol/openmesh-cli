#!/bin/bash

if [ -f hysteria2.pid ]; then
    PID=$(cat hysteria2.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        rm hysteria2.pid
        echo "Hysteria2 node2 stopped (PID: $PID)"
    else
        echo "Process $PID not running, removing stale PID file"
        rm hysteria2.pid
    fi
else
    echo "No PID file found"
fi
