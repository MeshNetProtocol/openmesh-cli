#!/bin/bash

HYSTERIA2_BIN="../hysteria2"

if [ ! -f "$HYSTERIA2_BIN" ]; then
    echo "Error: hysteria2 executable not found at $HYSTERIA2_BIN"
    exit 1
fi

mkdir -p logs

$HYSTERIA2_BIN server -c config.yaml > logs/stdout.log 2>&1 &

echo $! > hysteria2.pid

echo "Hysteria2 node2 started (PID: $!)"
echo "Listening on port 8444"
echo "Traffic stats API on 127.0.0.1:9444"
