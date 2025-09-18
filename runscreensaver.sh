#!/usr/bin/bash
# This script detects system idleness in Wayland using swayidle and runs randomly selected screensaver programs in /usr/bin starting with "screensaver-" during idle time.

# Ensure environment variables are set (important when started via KDE autostart)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# Configuration
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 50MB max log size
MAX_OLD_LOGS=3                      # Keep 3 old log files
IDLE_TIMEOUT=1                      # Timeout in minutes after which the system is considered idle
SCREENSAVER_SCRIPT="$HOME/Documents/bin/randscreensavers.sh"
RESUME_HANDLER_SCRIPT="$HOME/Documents/bin/resume_handler.sh"
IDLE_STATUS_FILE="/tmp/sway_idle_status"

mkdir -p "$(dirname "$LOGFILE")"

# --- Helper functions ---

# Initialize idle state as active (avoid stale "idle" leftover)
echo "active" > "$IDLE_STATUS_FILE"

# --- Helper functions ---
# --- Log rotation function ---
rotate_log() {
    if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="${LOGFILE}.${TIMESTAMP}.old"
        mv "$LOGFILE" "$BACKUP_FILE"
        echo "$(date) - LOG ROTATED: Previous log moved to $(basename "$BACKUP_FILE")" >> "$LOGFILE"

        # Clean up old logs (keep only MAX_OLD_LOGS)
        ls -t "${LOGFILE}".*.old 2>/dev/null | tail -n +$(($MAX_OLD_LOGS + 1)) | xargs rm -f --
    fi
}

# --- Helper functions ---
log_status() {
    rotate_log  # Check log rotation before writing
    echo "$(date) - Checking idle status" >> "$LOGFILE"
}

check_idle_status() {
    if [[ -f "$IDLE_STATUS_FILE" ]]; then
        idle_status=$(<"$IDLE_STATUS_FILE")
        echo "$(date) - Idle status: $idle_status" >> "$LOGFILE"

        if [[ "$idle_status" == "idle" ]]; then
            echo "$(date) - System is idle, running screensaver..." >> "$LOGFILE"
            # Kill old screensaver (if still running) before starting a new one
            pkill -f "screensaver-" 2>/dev/null
            "$SCREENSAVER_SCRIPT" &
        else
            echo "$(date) - System is active, ensuring screensaver is stopped..." >> "$LOGFILE"
            pkill -f "screensaver-" 2>/dev/null
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
    pkill -9 -f "$SCREENSAVER_SCRIPT"  # Force kill the screensaver loop if already running
    pkill -9 -f "screensaver-"             # Force kill any running screensaver
    check_idle_status
    sleep 15 # Check every 15 seconds for idle status (you can adjust this duration)
done
