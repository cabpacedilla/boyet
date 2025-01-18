#!/bin/bash

# Start the monitoring
notify-send "Battery Usage Monitoring Started" "Monitoring continuously every 1 hour." &

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
        sudo powertop --time=3600 --html=powertop.html

        # Extract top power consumers from the HTML file
        POWER_DATA=$(grep -A 12 "Top 10 Power Consumers" powertop.html | \
        grep "<tr" | \
        awk -F '>' '{gsub(/<\/t[dh]/, "", $3); gsub(/<\/t[dh]/, "", $5); gsub(/<\/t[dh]/, "", $7); gsub(/<\/t[dh]/, "", $9); \
        printf "%-8s %-8s %-10s %s\n", $3, $5, $7, $9}' | \
        head -n 12)

        # Check if POWER_DATA is empty
        if [ -z "$POWER_DATA" ]; then
            continue
        fi

        # Send notification with the top power consumers in a Konsole window
        konsole -e bash -c "echo -e \"Top 10 Power Consumers\n$POWER_DATA\n\"; read -p 'Press enter to close...'" &
    fi
done
