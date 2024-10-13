#!/bin/bash

# Set the interval between each notification in seconds (20 minutes)
INTERVAL=3600  # 1 hr

# Start the monitoring
notify-send "Battery Usage Monitoring Started" "Monitoring continuously every 1 hour."

# Infinite loop for monitoring
while true; do
    # Get power consumption data from powertop
    sudo powertop --html=powertop.html

	# Extract top power consumers from the HTML file
	POWER_DATA=$(grep -A 12 "Top 10 Power Consumers" powertop.html | \
	grep "<tr" | \
	awk -F '>' '{gsub(/<\/t[dh]/, "", $9); gsub(/<\/t[dh]/, "", $11); printf "%-8s %s\n", $11, $9}' | \
	head -n 12)
	
	# Check if POWER_DATA is empty
    if [ -z "$POWER_DATA" ]; then
        continue
    fi

	# Prepare the notification message
	MESSAGE="$POWER_DATA"

	# Send notification with the top power consumers
	konsole -e bash -c "echo -e \"Top 10 Power Consumers\n$MESSAGE\n\"; read -p 'Press enter to close...'" &

	# Wait for the specified interval
	sleep $INTERVAL
done
