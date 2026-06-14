#!/usr/bin/env bash

LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
LID_PATH="/proc/acpi/button/lid/LID0/state"

# Auto-detect AMD GPU brightness device
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

echo "$(date +%Y-%m-%d\ %H:%M:%S) - System is active again" >> "$LOGFILE"

# Kill screensavers (always do this)
pkill -9 -f "/home/claiveapa/Documents/bin/rand_screensavers.sh" 2>/dev/null
pkill -9 -f "screensaver-" 2>/dev/null

# Restore brightness if device found
if [ -n "$BRIGHT_DEVICE" ]; then
    brightnessctl --device="$BRIGHT_DEVICE" set 90%
else
    echo "$(date +%Y-%m-%d\ %H:%M:%S) - No amdgpu_bl* device found, skipping brightness restore." >> "$LOGFILE"
fi

# 🔒 LOCK THE SESSION on resume (this is the new step)
loginctl lock-session
echo "$(date '+%Y-%m-%d %H:%M:%S') - [SECURITY] Session locked on resume." >> "$LOGFILE"
