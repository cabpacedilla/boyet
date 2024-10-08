#!/bin/bash
while true; do
# Threshold for CPU usage (in percent) to consider a process as consuming resources
CPU_THRESHOLD=10

# Get idle CPU percentage using `sar`
IDLE_CPU=$(sar 1 1 | grep 'Average' | awk '{print $NF}')

# Check if the system is considered idle (you can adjust the threshold)
if (( $(echo "$IDLE_CPU > 90" | bc -l) )); then
	# List processes consuming more than the threshold CPU usage
	konsole -e bash -c "echo -e \"Top 10 CPU Consumers:\n\$(ps --sort=-%cpu -eo pid,%cpu,comm | head -n 11)\n\"; read -p 'Press enter to close...'" &
else
	:
fi

sleep 0.1s
done



