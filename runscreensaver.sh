#!/usr/bin/env bash
# This script detects system idleness in Wayland using swayidle and runs randomly selected screensaver programs in /usr/bin starting with "screensaver-" during idle time.
# In KDE 6.3, run one screensaver application in your screensavers folder then right click on the title bar 
# then cick configure special application settings in More Actions with the following settings
# 1. Window class (applicatoin) field = substring match for the start of the filenames of the screensavers "screensaver-"
# 2. Match whole window clas field = Yes
# 3. Window type field = All selected
# 4. Fullscreen Size & Position property = Force; Yes

# --- Environment Setup ---
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# --- Configuration ---
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 50MB
MAX_OLD_LOGS=3
IDLE_TIMEOUT=1                      # Minutes until idle
SCREENSAVER_SCRIPT="$HOME/Documents/bin/randscreensavers.sh"
RESUME_HANDLER_SCRIPT="$HOME/Documents/bin/resume_handler.sh"
IDLE_STATUS_FILE="/tmp/sway_idle_status"
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

# Ensure log directory exists and state is clean
mkdir -p "$(dirname "$LOGFILE")"
echo "active" > "$IDLE_STATUS_FILE"

# --- Helper: Log Rotation ---
rotate_log() {
    if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        mv "$LOGFILE" "${LOGFILE}.$(date '+%Y%m%d_%H%M%S').old"
        ls -t "${LOGFILE}".*.old 2>/dev/null | tail -n +$(($MAX_OLD_LOGS + 1)) | xargs rm -f --
    fi
}
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

# --- Core Logic: Idle Management ---
check_idle_status() {
    if [[ -f "$IDLE_STATUS_FILE" ]]; then
        idle_status=$(<"$IDLE_STATUS_FILE")

        if [[ "$idle_status" == "idle" ]]; then
            # 1. Start the NEXT screensaver in the background
            "$SCREENSAVER_SCRIPT" &
            
            # 2. FADE-IN OVERLAP (2 Seconds):
            # Gradually increase brightness from 0% to 100% over 2 seconds
            if [ -n "$BRIGHT_DEVICE" ]; then
                for i in {0..100..10}; do
                    brightnessctl -d "$BRIGHT_DEVICE" set "${i}%"
                    sleep 0.1
                done
            else
                sleep 3 # Fallback if no brightness device found
            fi
            
            # 3. Handle the Overlap cleanup:
            current_count=$(pgrep -c -f "screensaver-")
            
            if [ "$current_count" -gt 1 ]; then
                # Kill only the OLDEST instance, leaving the new one active
                pkill -o -f "screensaver-" 2>/dev/null
                echo "$(date) - Fade-in complete: Old screensaver killed." >> "$LOGFILE"
            else
                echo "$(date) - First run: Initial screensaver started." >> "$LOGFILE"
            fi
        else
            # System is ACTIVE: Stop all screensavers
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
rotate_log
start_swayidle &

# Main loop to continuously check idle status
while true; do
    log_status
    #pkill -9 -f "$SCREENSAVER_SCRIPT"  # Force kill the screensaver loop if already running
    #pkill -9 -f "screensaver-"             # Force kill any running screensaver
    check_idle_status
    sleep "$(shuf -i12-27 -n1)" # Check every 15 seconds for idle status (you can adjust this duration)
done
