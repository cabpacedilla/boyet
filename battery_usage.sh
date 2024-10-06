#!/bin/bash

# Set the interval between each notification in seconds (20 minutes)
INTERVAL=1200  # 20 minutes

# Start the monitoring
notify-send "Battery Usage Monitoring Started" "Monitoring continuously every 1 hour."

# Infinite loop for monitoring
while true; do
    # Get power consumption data from powertop
    powertop --html=powertop.html --time=$INTERVAL &>/dev/null

    # Extract top power consumers from the HTML file
    POWER_DATA=$(grep -A 10 "Top 10 Power Consumers" powertop.html | \
    grep "<tr" | \
    awk -F '>' '{gsub(/<\/t[dh]/, "", $9); gsub(/<\/t[dh]/, "", $11); printf "%-8s %s\n", $11, $9}' | \
    head -n 10)

    # Prepare the notification message
    MESSAGE="\n$POWER_DATA"

    # Send notification with the top power consumers
    echo -e "Top 10 Power Consumers" "$MESSAGE"
    # Wait for the specified interval (20 minutes)
    sleep $INTERVAL
done
