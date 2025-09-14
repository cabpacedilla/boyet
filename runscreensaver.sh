#!/usr/bin/bash
# This script detects system idleness in Wayland using swayidle and runs randomly selected screensaver programs in /usr/bin starting with "screensaver-" during idle time.

# Ensure environment variables are set (important when started via KDE autostart)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# Configuration
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
IDLE_TIMEOUT=1         # Timeout in minutes after which the system is considered idle
SCREENSAVER_SCRIPT="$HOME/Documents/bin/randscreensavers.sh"
RESUME_HANDLER_SCRIPT="$HOME/Documents/bin/resume_handler.sh"
IDLE_STATUS_FILE="/tmp/sway_idle_status"

mkdir -p "$(dirname "$LOGFILE")"

# Initialize idle state as active (avoid stale "idle" leftover)
echo "active" > "$IDLE_STATUS_FILE"

# --- Helper functions ---

log_status() {
    echo "$(date) - Checking idle status" >> "$LOGFILE"
}

check_idle_status() {
    if [[ -f "$IDLE_STATUS_FILE" ]]; then
        idle_status=$(<"$IDLE_STATUS_FILE")
        echo "$(date) - Idle status: $idle_status" >> "$LOGFILE"

        if [[ "$idle_status" == "idle" ]]; then
            if ! pgrep -f "screensaver-" >/dev/null; then
                echo "$(date) - System is idle, starting screensaver..." >> "$LOGFILE"
                "$SCREENSAVER_SCRIPT" &
            fi
        else
            if pgrep -f "screensaver-" >/dev/null; then
                echo "$(date) - System is active, stopping screensaver..." >> "$LOGFILE"
                pkill -f "screensaver-"
            fi
        fi
    else
        echo "$(date) - $IDLE_STATUS_FILE not found! swayidle may not be running correctly." >> "$LOGFILE"
    fi
}

start_swayidle() {
    echo "$(date) - Starting swayidle with timeout $((IDLE_TIMEOUT * 60)) seconds..." >> "$LOGFILE"
    swayidle -w \
        timeout $((IDLE_TIMEOUT * 60)) "echo idle > $IDLE_STATUS_FILE" \
        resume "echo active > $IDLE_STATUS_FILE && $RESUME_HANDLER_SCRIPT" &
}

# Start swayidle to track idle status and run screensaver when idle
start_swayidle &

# Main loop to continuously check idle status
while true; do
    log_status
    check_idle_status
    sleep 15 # Check every 15 seconds for idle status (you can adjust this duration)
done
