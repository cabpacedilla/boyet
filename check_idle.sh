#!/bin/bash
# Threshold for CPU usage (in percent) to consider a process as consuming resources
CPU_THRESHOLD=10

# Get idle CPU percentage using `sar`
IDLE_CPU=$(sar 1 1 | grep 'Average' | awk '{print $NF}')

while true; do
	# Check if the system is considered idle (you can adjust the threshold)
	if (( $(echo "$IDLE_CPU > 90" | bc -l) )); then
	    # List processes consuming more than the threshold CPU usage
		notify-send --app-name "Idle power hog:" "Processes consuming more than $CPU_THRESHOLD% CPU:"
		ps --sort=-%cpu -eo pid,%cpu,comm | awk -v threshold="$CPU_THRESHOLD" '$2 > threshold {print $0}'
	else
	    :
	fi
	
	sleep 0.1s
done

