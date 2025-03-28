#!/bin/bash

# Configuration
IDLE_TIMEOUT=10        # Time in minutes after which the system is considered idle
CPU_THRESHOLD=10       # CPU usage threshold in percentage
MEMORY_THRESHOLD=10    # Memory usage threshold in percentage
DISK_IO_THRESHOLD=5    # Disk I/O threshold in MB/s
LOG_FILE="~/scriptlogs/abnormal_resource_usage.log"
IDLE_STATUS_FILE="/tmp/sway_idle_status"  # Temporary file to track idle state

# Function to check resource usage
check_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*id, *\([0-9.]*\)%.*/\1" | awk '{print 100 - $1}')
    local mem_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }')
    local disk_io=$(iostat -m 1 2 | awk 'NR==4 {print $3+$4}')

    local current_time=$(date +"%Y-%m-%d %H:%M:%S")

    if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
        notify-send "Abnormal CPU Usage" "$current_time - Abnormal CPU usage: $cpu_usage%"
        sudo echo "$current_time - Abnormal CPU usage: $cpu_usage%" >> "$LOG_FILE"
        ps aux --sort=-%cpu | head -n 10 >> "$LOG_FILE"
    fi

    if (( $(echo "$mem_usage > $MEMORY_THRESHOLD" | bc -l) )); then
        notify-send "Abnormal Memory Usage" "$current_time - Abnormal memory usage: $mem_usage%"
        sudo echo "$current_time - Abnormal memory usage: $mem_usage%" >> "$LOG_FILE"
        ps aux --sort=-%mem | head -n 10 >> "$LOG_FILE"
    fi

    if (( $(echo "$disk_io > $DISK_IO_THRESHOLD" | bc -l) )); then
        notify-send "Abnormal Disk I/O" "$current_time - Abnormal Disk I/O: $disk_io MB/s"
        sudo echo "$current_time - Abnormal Disk I/O: $disk_io MB/s" >> "$LOG_FILE"
        iotop -boP -n 1 >> "$LOG_FILE"
    fi
}

# Use swayidle to detect when the system is idle
start_swayidle() {
    # Start swayidle with timeout for idle check and an output file for idle status
    swayidle -w timeout $((IDLE_TIMEOUT * 60)) 'echo idle > /tmp/sway_idle_status' resume 'echo active > /tmp/sway_idle_status'
}

# Check if the system is idle by reading the status file
check_idle_status() {
    if [[ -f "$IDLE_STATUS_FILE" ]]; then
        idle_status=$(cat "$IDLE_STATUS_FILE")
        if [[ "$idle_status" == "idle" ]]; then
            echo "System is idle. Checking resources..."
            check_resources
        fi
    fi
}

# Start swayidle to track idle status and monitor resources while idle
start_swayidle &

# Main loop to continuously check idle status
while true; do
    check_idle_status
    sleep 60  # Check every minute for idle status
done
