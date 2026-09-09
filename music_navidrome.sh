#!/bin/bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# Start Navidrome on port 8081
/usr/local/bin/navidrome --configfile /home/claiveapa/.config/navidrome/navidrome.toml &

# Wait for Navidrome to initialize
sleep 5

# Start zrok share (agent already running from wallpaper service)
/usr/bin/zrok share reserved --headless boyetaudio >> /home/claiveapa/music_url.log 2>&1 &

# Keep script alive
wait
