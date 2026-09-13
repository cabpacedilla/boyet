#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# ============================================================================
# Called by swayidle on resume. Kills screensavers, restores brightness,
# and locks the session.
# ============================================================================

LOGFILE="$HOME/scriptlogs/screensaver_log.txt"

echo "$(date '+%Y-%m-%d %H:%M:%S') - System is active again" >> "$LOGFILE"

# --- Kill screensavers ---
pkill -9 -f "$HOME/Documents/bin/random-screensaver.sh" 2>/dev/null
pkill -9 -f "screensaver-" 2>/dev/null

# --- Restore brightness (AMD GPU auto-detect) ---
BRIGHT_DEVICE=$(brightnessctl -l 2>/dev/null | grep -o "amdgpu_bl[0-9]" | head -n1)

if [ -n "$BRIGHT_DEVICE" ]; then
    brightnessctl --device="$BRIGHT_DEVICE" set 90%
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Brightness restored on $BRIGHT_DEVICE" >> "$LOGFILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - No amdgpu_bl* device found, skipping brightness restore." >> "$LOGFILE"
fi

# --- Lock the session ---
loginctl lock-session
echo "$(date '+%Y-%m-%d %H:%M:%S') - [SECURITY] Session locked on resume." >> "$LOGFILE"
