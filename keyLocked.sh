#!/usr/bin/env bash
# This script will notify when Caps Lock or Num Lock are on using the xset q command.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like keyLocked.sh
# 4. Make file executable with chmod +x keyLocked.sh command
# 5. Add the keyLocked.sh command in Startup applications
# 6. Reboot the laptop
# 7. Press the Caps Lock key
# 8. A Caps Lock key notification message will be displayed
# 9. Press the Num Lock key
# 10. A Num Lock key notification message will be displayed

# Define LED mask values for key locks
CAPS_LOCK="00000001"
NUM_LOCK="00000002"
CAPSNUM_LOCK="00000003"
NO_LOCK="00000000"

# Function to get LED mask value
get_led_mask() {
    xset q | grep 'LED mask' | awk '{ print $NF }'
}

# Main loop
while true; do
    LED_MASK=$(get_led_mask)

    # Check if the LED mask command was successful
    if [ $? -ne 0 ]; then
        sleep 10
        continue
    fi

    # Notify based on LED mask value
    case "$LED_MASK" in
        "$CAPS_LOCK")
            notify-send -t 9000 --app-name "⚠️ Key lock:" "Caps lock is on."
            ;;
        "$NUM_LOCK")
            notify-send -t 9000 --app-name "⚠️ Key lock:" "Num lock is on."
            ;;
        "$CAPSNUM_LOCK")
            notify-send -t 9000 --app-name "⚠️ Key lock:" "Caps lock and Num lock are on."
            ;;
        "$NO_LOCK")
            # Do nothing
            ;;
        *)
            # Handle unexpected values
            ;;
    esac

    sleep 10
done

