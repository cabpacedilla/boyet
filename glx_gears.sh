#!/bin/bash

# Run glxgears, capture stderr, and extract the last FPS value
fps=$(glxgears 2>&1 | awk '/FPS/ {print $3}' | tail -1 | cut -d. -f1)

# Compare FPS to 60 and send notification
if [ "$fps" -gt 60 ]; then
    notify-send "PASS: glxgears FPS > 60" "Current FPS: $fps"
else
    notify-send "FAIL: glxgears FPS <= 60" "Current FPS: $fps"
fi
