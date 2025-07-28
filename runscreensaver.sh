# In KDE 6.3, run one screensaver application in your screensavers folder then right click on the title bar 
# then cick configure special application settings in More Actions with the following settings
# 1. Window class (applicatoin) field = substring match for the start of the filenames of the screensavers "screensaver-"
# 2. Match whole window clas field = Yes
# 3. Window type field = All selected
# 4. Fullscreen Size & Poristion property = Force; Yes

runscreensaver.sh
------------------
#!/usr/bin/bash
# This script detects system idleness in Wayland using swayidle and runs randomly selected screensaver programs in /usr/bin starting with "screensaver-" during idle time.

# Configuration
LOGFILE=~/scriptlogs/screensaver_log.txt
IDLE_TIMEOUT=1         # Timeout in minutes after which the system is considered idle
SCREENSAVER_SCRIPT="/home/claiveapa/bin/rand_screensavers.sh"
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
    swayidle -w timeout $((IDLE_TIMEOUT * 60)) 'echo idle > /tmp/sway_idle_status' resume 'echo active > /tmp/sway_idle_status && ~/bin/resume_handler.sh'
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


rand_screensavers.sh
------------------------
#!/usr/bin/bash
# This script runs randomly selected rss-glx programs every minute.

LOGFILE="$HOME/scriptlogs/idle_log.txt"
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl0/brightness
MINIMAL=0
OPTIMAL=49961

# --- UPDATED LOCATION FOR SCREENSAVER LISTS ---
# File to store the list of screensavers that have NOT yet been played in the current cycle
UNPLAYED_LIST="$HOME/scriptlogs/unplayed_screensavers.txt"
# File to store the list of screensavers that HAVE been played in the current cycle
PLAYED_LIST="$HOME/scriptlogs/played_screensavers.txt"
# --- END UPDATED LOCATION ---

# Directory containing all screensaver programs
SCREENSAVER_DIR="$HOME/screensavers"

# Ensure the log directory exists (this also covers the new list files)
mkdir -p "$HOME/scriptlogs"


# Function to check if a media player is running
is_media_playing() {
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    if [ -n "$MEDIA_PLAY" ]; then
        return 0 # Media is playing
    else
        return 1 # Media is not playing
    fi
}

# Function to initialize or refresh the unplayed list
initialize_screensaver_lists() {
    # If the unplayed list doesn't exist or is empty, or if played list is missing,
    # re-populate unplayed list with all screensavers and clear played list.
    if [ ! -f "$UNPLAYED_LIST" ] || [ ! -s "$UNPLAYED_LIST" ] || [ ! -f "$PLAYED_LIST" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Initializing/Resetting screensaver play order." >> "$LOGFILE"
        find "$SCREENSAVER_DIR" -maxdepth 1 -type f -name "screensaver-*" -perm /u+x -print0 | shuf -z | xargs -0 -n 1 basename > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST" # Clear the played list
    fi
}

# --- Main Script Logic ---

# Perform initial list check/setup on every run
initialize_screensaver_lists

if ! is_media_playing; then
    # Kill the previous screensaver if it is running
    pkill -9 -f screensaver- # Force Kill the screensaver

    echo $MINIMAL | sudo tee $BRIGHT_PATH &
    sleep 0.1

    # Read the available screensavers from the unplayed list
    mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
    NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}

    if [ "$NUM_UNPLAYED" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - All screensavers played in this cycle. Resetting cycle." >> "$LOGFILE"
        # Move all screensavers from played to unplayed, then shuffle
        cat "$PLAYED_LIST" | shuf > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST" # Clear the played list
        mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
        NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}
        if [ "$NUM_UNPLAYED" -eq 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: No screensavers found in $SCREENSAVER_DIR after reset. Aborting." >> "$LOGFILE"
            exit 1
        fi
    fi

    # Select a random screensaver from the unplayed list
    RANDOM_INDEX=$(( RANDOM % NUM_UNPLAYED ))
    SELECTED_BASENAME="${UNPLAYED_SCREENSAVERS[RANDOM_INDEX]}"
    RANDOM_PROGRAM="$SCREENSAVER_DIR/$SELECTED_BASENAME"

    # Remove the selected screensaver from UNPLAYED_LIST and add to PLAYED_LIST
    # Using sed to remove the line from UNPLAYED_LIST
    RANDOM_INDEX_PLUS_1=$((RANDOM_INDEX + 1)) # Calculate for sed's 1-based indexing
    sed -i "${RANDOM_INDEX_PLUS_1}d" "$UNPLAYED_LIST"
    echo "$SELECTED_BASENAME" >> "$PLAYED_LIST"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_PROGRAM (Remaining unplayed: $((NUM_UNPLAYED - 1)))" >> "$LOGFILE"

    # Run the screensaver
    "$RANDOM_PROGRAM" &
    sleep 0.5
    echo $OPTIMAL | sudo tee $BRIGHT_PATH

else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Media player is running, skipping screensaver" >> "$LOGFILE"
fi



resume_handler.sh
------------------
#!/usr/bin/bash
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
LID_PATH="/proc/acpi/button/lid/LID0/state"
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl0/brightness
OPTIMAL=49961

echo "$(date +%Y-%m-%d\ %H:%M:%S) - System is active again" >> $LOGFILE

# Function to get the lid state
get_lid_state() {
    local LID_STATE
    if [ -f "$LID_PATH" ]; then
        LID_STATE=$(awk '{print $2}' < "$LID_PATH")
    fi
    echo "$LID_STATE"
}

is_media_playing() {
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    if [ -n "$MEDIA_PLAY" ]; then
        return 0
    else
        return 1
    fi
}

if ! is_media_playing && [ "$(get_lid_state)" == "open" ]; then
    # Kill any running screensaver programs
    pkill -9 -f "/home/claiveapa/Documents/bin/rand_screensavers.sh"  # Force Kill the loop!
    pkill -9 -f screensaver- # Force Kill the screensaver
    qdbus org.kde.screensaver /ScreenSaver Lock
    brightnessctl --device=amdgpu_bl0 set 80%
else
    :
fi







