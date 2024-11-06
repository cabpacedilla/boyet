#!/bin/bash
# Threshold for CPU usage (in percent) to consider a process as consuming resources
CPU_THRESHOLD=70

while true; do
    # Get idle CPU percentage using `sar`
    IDLE_CPU=$(sar 1 1 | grep 'Average' | awk '{print $NF}')
    
    # Calculate CPU usage by subtracting idle CPU from 100
    CPU_USAGE=$(echo "100 - $IDLE_CPU" | bc)

    # Check if CPU usage is above the threshold (i.e., system is under load)
    if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
        # List processes consuming more than the threshold CPU usage
        konsole -e bash -c "echo -e \"Top 10 CPU Consumers:\n\$(ps --sort=-%cpu -eo pid,%cpu,comm | head -n 11)\n\"; read -p 'Press enter to close...'" &
    else
        # System is idle, do nothing or continue to the next check
        :
    fi

    # Wait for 1 minute before checking again
    sleep 1m
done
