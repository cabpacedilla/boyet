#!/usr/bin/env bash
# This script will alert the power consumption in a given time
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2024

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like battery_usage.sh
# 4. Make file executable with command chmod +x battery_usage.sh 
# 5. Add the battery_usage.sh command in Startup applications
# 6. Reboot the laptop
# 7. Log in and simulate low memory scenario by running many high memory consuming processes until free memory space reaches desired low free memory space in megabytes
# 8. Low memory alert message will be displayed
#!/usr/bin/bash

# Start the monitoring
notify-send "✅ Battery Usage Monitoring Started" "Monitoring continuously every 45 hour." &

# Terminal list for flexibility across desktop environments
TERMINALS=("gnome-terminal" "xfce4-terminal" "tilix" "lxterminal" "mate-terminal" "alacritty" "urxvt" "konsole")

# Flag to indicate if it's the first run
first_run=true

# Infinite loop for monitoring
while true; do
    # Check if it's the first run
    if [ "$first_run" = true ]; then
        # Skip running powertop on the first iteration and mark as no longer the first run
        first_run=false
    else
        # Get power consumption data from powertop
        sudo powertop --time=2700 --html=powertop.html

        # Extract top power consumers from the HTML file
        POWER_DATA=$(grep -A 12 "Top 10 Power Consumers" powertop.html | \
        grep "<tr" | \
        awk -F '>' '{gsub(/<\/t[dh]/, "", $3); gsub(/<\/t[dh]/, "", $5); gsub(/<\/t[dh]/, "", $7); gsub(/<\/t[dh]/, "", $9); \
        if (length($9) > 119) $9 = substr($9, 1, 110) "..."; \
        printf "%-14s %-10s %-10s %s\n", $3, $5, $7, $9}' | \
        head -n 11)

        # Check if POWER_DATA is empty
        if [ -z "$POWER_DATA" ]; then
            continue
        fi

        # Try launching in available terminal
        launched=false
        for term in "${TERMINALS[@]}"; do
            if command -v "$term" >/dev/null 2>&1; then
                "$term" -e bash -c "echo -e \"Top 10 Power Consumers\n$POWER_DATA\n\"; read -p 'Press enter to close...'" &
                launched=true
                break
            fi
        done

        # If no terminal was found, notify the user
        if [ "$launched" = false ]; then
            notify-send "⚠️ Battery Usage Alert" "No supported terminal emulator found to display power usage."
        fi
    fi
done
