#!/bin/bash

cd "/home/claiveapa/Documents/lychee"

# Start Lychee (if not already running)
podman-compose up -d

# Wait for it to be ready
sleep 10

# Start zrok agent (kill any old ones first)
pkill zrok 2>/dev/null
/usr/bin/zrok agent start &
sleep 3

# Share Lychee on port 8080
/usr/bin/zrok share reserved --headless --port 8080 wallpapers >> /home/claiveapa/wallpaper_url.log 2>&1 &

# Keep the script alive
wait
