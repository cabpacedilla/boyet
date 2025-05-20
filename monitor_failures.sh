#!/bin/bash
# monitor_fedora_failures.sh
#
# This script monitors key Fedora system logs for errors and failures in real time.
# It checks the log files:
#   - /var/log/messages : general system messages on Fedora
#   - /var/log/secure   : authentication and security-related logs
#
# It also monitors the systemd journal for error-level logs.
#
# You can modify the KEYWORDS and LOGFILES arrays as needed.

# Path to the alert log file (modify as needed)
ALERT_LOG=~/scriptlogs/monitor_alerts.log

# Keywords to search for in log entries (case-insensitive)
KEYWORDS="error|fail|panic|segfault|OOM"

# Array of Fedora-specific log files to monitor.
LOGFILES=(
    "/var/log/messages"   # General system messages
    "/var/log/secure"     # Security and authentication logs
    # Optionally, add other logs, e.g., "/var/log/audit/audit.log"
)

# Array to store background process IDs so we can clean them up on exit.
pids=()

# Function to monitor a specific log file
monitor_log_file() {
    local logfile="$1"
    if [ ! -f "$logfile" ]; then
        echo "Log file '$logfile' not found. Skipping..."
        return
    fi
    echo "Monitoring $logfile for failures..."
    # Use tail -F to follow the file even if it is rotated
    sudo tail -n 0 -F "$logfile" | while read -r line; do
        if echo "$line" | grep -Ei "$KEYWORDS" > /dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $logfile: $line" >> "$ALERT_LOG"
            # Additional actions can be added here (e.g., email alerts)
        fi
    done &
    pids+=($!)
}

# Monitor each specified log file
for logfile in "${LOGFILES[@]}"; do
    monitor_log_file "$logfile"
done

# Check if journalctl is available and monitor systemd journal logs
if command -v journalctl > /dev/null; then
    echo "Monitoring systemd journal for error logs..."
    # -f: follow log output, -p 3: only show priority "error" and above
    journalctl -f -p 3 | while read -r line; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] journal: $line" >> "$ALERT_LOG"
    done &
    pids+=($!)
fi

# Cleanup function to kill background monitoring processes on exit
cleanup() {
    echo "Terminating monitoring processes..."
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null
    done
    exit 0
}

# Trap SIGINT and SIGTERM signals (e.g., Ctrl+C) to run cleanup
trap cleanup SIGINT SIGTERM

# Wait indefinitely so background processes continue to run
wait
