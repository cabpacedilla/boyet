#!/usr/bin/bash
# This script detects system idleness in Wayland using swayidle and runs randomly selected screensaver programs in /usr/bin starting with "rss-glx-" during idle time.

LOGFILE=~/scriptlogs/screensaver_log.txt

while true; do

# Kill previous instances
pkill -9 -f "/home/claiveapa/bin/run_rss_glx_programs.sh"   # Force Kill the loop!
pkill -9 -f rss-glx- # Force Kill the screensaver

swayidle -w \
    timeout 120 "env WAYLAND_DISPLAY= ~/bin/run_rss_glx_programs.sh" \
    resume "/home/claiveapa/bin/resume_handler.sh" \
    #before-sleep "/home/claiveapa/bin/resume_handler.sh"
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
