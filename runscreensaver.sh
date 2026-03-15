#!/usr/bin/env bash
# This script detects system idleness in Wayland using swayidle and runs randomly selected screensaver programs in /usr/bin starting with "screensaver-" during idle time.
# In KDE 6.3, run one screensaver application in your screensavers folder then right click on the title bar
# then cick configure special application settings in More Actions with the following settings
# 1. Window class (applicatoin) field = substring match for the start of the filenames of the screensavers "screensaver-"
# 2. Match whole window clas field = Yes
# 3. Window type field = All selected
# 4. Fullscreen Size & Position property = Force; Yes

LOCK_FILE="/tmp/runscreensaver_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

# --- Environment Setup ---
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# --- Configuration ---
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 50MB
MAX_OLD_LOGS=3
IDLE_TIMEOUT=1                       # Minutes until idle
SCREENSAVER_SCRIPT="$HOME/Documents/bin/randscreensavers.sh"
RESUME_HANDLER_SCRIPT="$HOME/Documents/bin/resume_handler.sh"
IDLE_STATUS_FILE="/tmp/sway_idle_status"

# Ensure log directory exists and state is clean
mkdir -p "$(dirname "$LOGFILE")"

# --- Helper functions ---
rotate_log() {
    if [ -f "$LOGFILE" ] && [ "$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOGFILE" "${LOGFILE}.$(date '+%Y%m%d_%H%M%S').old"
        ls -t "${LOGFILE}".*.old 2>/dev/null | tail -n +$((MAX_OLD_LOGS + 1)) | xargs rm -f --
    fi
}

# Initialize idle state as active (avoid stale "idle" leftover)
echo "active" > "$IDLE_STATUS_FILE"

log_status() {
    rotate_log  # Check log rotation before writing
    echo "$(date) - Checking idle status" >> "$LOGFILE"
}

# --- Core Logic: Idle Management ---
check_idle_status() {
    if [[ -f "$IDLE_STATUS_FILE" ]]; then
        idle_status=$(<"$IDLE_STATUS_FILE")

        if [[ "$idle_status" == "idle" ]]; then
            # 1. Start the NEXT screensaver in the background
            # This allows it to load while the current one is still visible
            "$SCREENSAVER_SCRIPT" &

            # 2. Transition Window: Wait for the new screensaver to initialize
            # This prevents the "black flash" between programs.
            #sleep 2

            # 3. Handle the Overlap:
            # pgrep -c counts how many screensavers are currently running.
            current_count=$(pgrep -c -f "screensaver-")

            if [ "$current_count" -gt 1 ]; then
                # If more than one is running, kill the OLDEST instance only (-o)
                pkill -o -f "screensaver-" 2>/dev/null
                echo "$(date) - Transition complete: New screensaver active, old one killed." >> "$LOGFILE"
            else
                # On the very first run, we don't kill anything.
                echo "$(date) - First run: Initial screensaver started." >> "$LOGFILE"
            fi
        else
            # System is ACTIVE: Stop all screensaver processes immediately
            pkill -f "screensaver-" 2>/dev/null
            echo "$(date) - System active: All screensavers stopped." >> "$LOGFILE"
        fi
    fi
}

# --- Background Task: Swayidle ---
start_swayidle() {
    # Clean up any existing swayidle instances first
    pkill -f "swayidle" 2>/dev/null

    echo "$(date) - Starting swayidle (Timeout: $((IDLE_TIMEOUT * 60))s)" >> "$LOGFILE"
    swayidle -w \
        timeout $((IDLE_TIMEOUT * 60)) "echo idle > $IDLE_STATUS_FILE" \
        resume "echo active > $IDLE_STATUS_FILE && $RESUME_HANDLER_SCRIPT" &
}

# --- Execution ---
start_swayidle

# Main loop to continuously check idle status
while true; do
    log_status
    check_idle_status
    sleep 10 # Check every 10 seconds for idle status (you can adjust this duration)
done
