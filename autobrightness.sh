#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# ============================================================
# Auto Brightness (Event-Driven)
# ============================================================
# Watches the brightness file via inotifywait. When the
# brightness changes, it immediately corrects it to 100%.
# 
# Dependency: 
# Install inotifywait with sudo dnf install inotify-tools
# ============================================================

# --- Single-Instance Lock ---
LOCK_FILE="/tmp/autobrightness_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

# --- Cleanup ---
cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

trap cleanup EXIT

# --- Detect Backlight Device ---
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
if [ -z "$DEVICE" ]; then
    echo "No amdgpu backlight device found." >&2
    exit 1
fi

BRIGHTNESS_FILE="/sys/class/backlight/${DEVICE}/brightness"
MAX_BRIGHTNESS=$(cat "/sys/class/backlight/${DEVICE}/max_brightness" 2>/dev/null)
TARGET_PERCENT=90

if [ -z "$MAX_BRIGHTNESS" ]; then
    echo "Cannot read max brightness for $DEVICE" >&2
    exit 1
fi

# Calculate the target absolute brightness value
TARGET_VALUE=$(( MAX_BRIGHTNESS * TARGET_PERCENT / 100 ))

# --- Core Function ---
check_and_correct() {
    CURRENT_BRIGHTNESS=$(cat "$BRIGHTNESS_FILE" 2>/dev/null)
    if [[ -n "$CURRENT_BRIGHTNESS" && "$CURRENT_BRIGHTNESS" -ne "$TARGET_VALUE" ]]; then
        brightnessctl -d "$DEVICE" set "${TARGET_PERCENT}%"
    fi
}

# --- Initial check (catch current state) ---
check_and_correct

# --- Main Event Loop ---
# Wait for the brightness file to be modified.
# Every time it changes, run check_and_correct.
inotifywait -m -e modify "$BRIGHTNESS_FILE" 2>/dev/null | while read -r; do
    check_and_correct
done
