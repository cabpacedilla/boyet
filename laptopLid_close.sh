#!/usr/bin/bash
# This script will activate screen lock when the laptop lid will be closed for auto lid close security in icewm window manager in Linux
# This script was written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# Steps for the task:
# 1. icewm is already installed and configured for user login
# 2. Install xscreensaver
# 3. Create a bin directory inside your home directory
# 4. Change directory to the bin directory
# 5. Create the bash script file below with nano or gedit and save it with a filename like lid_close.sh
# 6. Make file executable with chmod +x lid_close.sh command
# 7. Add the "lid_close.sh &" command in .icewm/startup script
# 8. Reboot the laptop
# 9. Login to icewm
# 10. Close the laptop lid
# 11. Open the laptop lid
# 12. xscreensaver will ask for password

#!/usr/bin/bash
# Pre-requisite: 
# Install xscreensaver and run xscreensaver at startup

# Path to lid state file
LID_PATH="/proc/acpi/button/lid/LID0/state"
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl0/brightness
OPTIMAL=49961

# Function to check if HDMI is connected
check_hdmi() {
    local HDMI_DETECT
    HDMI_DETECT=$(xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}')
    echo "$HDMI_DETECT"
}

# Function to get the lid state
get_lid_state() {
    local LID_STATE
    if [ -f "$LID_PATH" ]; then
        LID_STATE=$(awk '{print $2}' < "$LID_PATH")
    fi
    echo "$LID_STATE"
}

# Main loop
while true; do
    # Check lid state and HDMI connection
    if [ "$(get_lid_state)" == "closed" ] && [ -z  "$(check_hdmi)" ]; then
        # Lock screen and suspend if no HDMI is connected and lid is closed
        echo $OPTIMAL | sudo tee $BRIGHT_PATH
        #xscreensaver-command --lock
        systemctl suspend
    else
		:
    fi

    sleep 0.1
done






