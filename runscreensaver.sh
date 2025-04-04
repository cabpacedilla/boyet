#!/usr/bin/bash
# This script detects system idleness in Wayland using swayidle and runs randomly selected screensaver programs in /usr/bin starting with "rss-glx-" during idle time.

# Configuration
LOGFILE=~/scriptlogs/screensaver_log.txt
IDLE_TIMEOUT=1         # Timeout in minutes after which the system is considered idle
SCREENSAVER_SCRIPT="/home/claiveapa/bin/run_rss_glx_programs.sh"
RESUME_HANDLER_SCRIPT="/home/claiveapa/bin/resume_handler.sh"
IDLE_STATUS_FILE="/tmp/sway_idle_status"  # Temporary file to track idle state

# Function to log status for debugging
log_status() {
    echo "$(date) - Checking idle status" >> "$LOGFILE"
}

# Function to check if the system is idle by reading the status file
check_idle_status() {
    if [[ -f "$IDLE_STATUS_FILE" ]]; then
        idle_status=$(cat "$IDLE_STATUS_FILE")
        echo "$(date) - Idle status: $idle_status" >> "$LOGFILE"  # Log idle status

        if [[ "$idle_status" == "idle" ]]; then
            echo "$(date) - System is idle, running screensaver..." >> "$LOGFILE"
            # Run the screensaver script here (you can add random selection logic or just run it)
            "$SCREENSAVER_SCRIPT"
        else
            echo "$(date) - System is not idle, skipping screensaver..." >> "$LOGFILE"
        fi
    else
        echo "$(date) - $IDLE_STATUS_FILE not found! swayidle may not be running correctly." >> "$LOGFILE"
    fi
}

# Function to start swayidle
start_swayidle() {
    echo "$(date) - Starting swayidle with timeout $((IDLE_TIMEOUT * 60)) seconds..." >> "$LOGFILE"
    # Start swayidle with timeout for idle state, and update the idle status file on idle/active
    swayidle -w timeout $((IDLE_TIMEOUT * 60)) \
        'echo idle > /tmp/sway_idle_status' resume 'echo active > /tmp/sway_idle_status'
}

# Main script logic
# Kill any previous instances of the screensaver script or processes
echo "$(date) - Killing any previous screensaver or swayidle processes..." >> "$LOGFILE"
pkill -9 -f "$SCREENSAVER_SCRIPT"  # Force kill the screensaver loop if already running
pkill -9 -f "rss-glx-"             # Force kill any running screensaver

# Start swayidle to track idle status and run screensaver when idle
start_swayidle &

# Main loop to continuously check idle status
while true; do
    log_status
    check_idle_status
    sleep 15 # Check every 15 seconds for idle status (you can adjust this duration)
done



run_rss_glx_programs.sh
------------------------
#!/usr/bin/bash
# This script runs randomly selected rss-glx programs every minute.

LOGFILE=~/scriptlogs/idle_log.txt

# Function to check if a media player is running
is_media_playing() {
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    if [ -n "$MEDIA_PLAY" ]; then
        return 0
    else
        return 1
    fi
}


if ! is_media_playing; then
    # Kill the previous screensaver if it is running
    pkill -9 -f rss-glx- # Force Kill the screensaver

    RSS_GLX_PROGRAMS=(/usr/bin/rss-glx-*)
    RANDOM_PROGRAM=${RSS_GLX_PROGRAMS[RANDOM % ${#RSS_GLX_PROGRAMS[@]}]}
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_PROGRAM" >> "$LOGFILE"
    $RANDOM_PROGRAM &
    sleep 15
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Media player is running, skipping screensaver" >> "$LOGFILE"
fi


resume_handler.sh
------------------
#!/usr/bin/bash
LOGFILE=~/scriptlogs/screensaver_log.txt
echo "$(date +%Y-%m-%d\ %H:%M:%S) - System is active again" >> $LOGFILE

# Kill any running screensaver programs
pkill -9 -f "/home/claiveapa/bin/run_rss_glx_programs.sh"  # Force Kill the loop!
pkill -9 -f rss-glx- # Force Kill the screensaver
