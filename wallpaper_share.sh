#!/bin/bash

cd "/run/media/claiveapa/Data/claive/Documents/nobara/wallpapers/"

# Start miniserve with thumbnail gallery and index page
miniserve --port 8080 . &

sleep 2

# Use the reserved zrok share (permanent URL)
/usr/bin/zrok share reserved --headless wallpapers >> /home/claiveapa/wallpaper_url.log 2>&1

wait
