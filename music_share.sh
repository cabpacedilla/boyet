#!/bin/bash

cd "/home/claiveapa/Music/"

# Start miniserve with thumbnail gallery and index page
/usr/local/bin/miniserve --port 8081 . &

# Wait for miniserve to initialize
sleep 2

# Start the zrok agent (this runs in the background)
/usr/bin/zrok agent start

# Wait for the agent to be ready
sleep 3

# Use the reserved zrok share (permanent URL) – run in background
/usr/bin/zrok share reserved --headless boyetaudio >> /home/claiveapa/music_url.log 2>&1 &

# Keep the script alive
wait
