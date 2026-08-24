#!/bin/bash

exec > /tmp/zrok-wrapper.log 2>&1

echo "$(date): ===== Starting zrok wrapper ====="

# Kill only actual zrok processes (not this script)
pkill zrok 2>/dev/null || true

# Remove stale socket
rm -f /home/claiveapa/.zrok/agent.socket 2>/dev/null || true

echo "$(date): Starting zrok agent..."
/usr/bin/zrok agent start &

echo "$(date): Waiting 10 seconds for agent to connect..."
sleep 10

echo "$(date): Sharing wallpapers4..."
/usr/bin/zrok share reserved --headless wallpapers4 &

echo "$(date): Sharing navidrome..."
/usr/bin/zrok share reserved --headless navidrome &

echo "$(date): All processes launched. Waiting for children..."
wait
