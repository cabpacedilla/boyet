#!/usr/bin/env bash
# Low Memory Alert Script (with total usage check)
# Alerts when free memory (available) <= threshold of total RAM
# Shows top N memory consumers and total memory usage
# Uses notify-send for alerts

MEMFREE_LIMIT_PERCENT=15       # Alert threshold (%)
CHECK_INTERVAL=30              # Seconds between checks
MAX_PROCESSES=10               # Top N processes/trees to display
LOG_FILE="$HOME/lowmem_alert.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))   # 50 MB

# Rotate log if it grows too large
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(stat -c%s "$LOG_FILE")
        if [ "$LOG_SIZE" -ge "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d%H%M%S).bak"
            touch "$LOG_FILE"
        fi
    fi
}

# Get top processes (grouped by command)
get_top_processes() {
    ps -eo comm,%mem,rss --no-headers | \
    awk -v total_mem="$TOTAL_MEM" '
    {
        mem[$1]+=$2;   # %mem by command
        rss[$1]+=$3;   # rss in KB
        count[$1]++;   # number of procs
    }
    END {
        for (cmd in mem) {
            size_mb = rss[cmd] / 1024;                # KB -> MB
            size_str = (size_mb >= 1024) ? sprintf("%.1f GB", size_mb/1024) : sprintf("%.0f MB", size_mb);
            printf "%s: %.2f%% (%s, %d proc)\n", cmd, mem[cmd], size_str, count[cmd];
        }
    }' | sort -k2 -nr | head -n "$MAX_PROCESSES"
}

while true; do
    TOTAL_MEM=$(free -m | awk 'NR==2 {print $2}')   # Total RAM MB
    MEMFREE=$(free -m | awk 'NR==2 {print $7}')     # Available RAM MB
    THRESHOLD=$(( TOTAL_MEM * MEMFREE_LIMIT_PERCENT / 100 ))

    if [[ "$MEMFREE" =~ ^[0-9]+$ ]] && [ "$MEMFREE" -le "$THRESHOLD" ]; then
        TOP_PROCESSES=$(get_top_processes)

        # Calculate total used memory (all processes RSS)
        TOTAL_USED=$(ps -eo rss --no-headers | awk '{sum+=$1} END {print sum}')
        TOTAL_USED_MB=$(( TOTAL_USED / 1024 ))
        TOTAL_USED_STR=$TOTAL_USED_MB
        [ "$TOTAL_USED_MB" -ge 1024 ] && TOTAL_USED_STR="$(awk -v mb=$TOTAL_USED_MB 'BEGIN{printf "%.1f GB", mb/1024}') MB"

        NOTIF="Total used by processes: ${TOTAL_USED_MB} MB
Available=${MEMFREE}MB (Threshold=${THRESHOLD}MB)
Top memory users:
$TOP_PROCESSES"

        # Log
        {
            echo "[$(date)] $NOTIF"
            echo
        } >> "$LOG_FILE"
        rotate_log

        # Notify
        notify-send -u critical "⚠ Low Memory Alert" "$NOTIF"
    fi

    sleep "$CHECK_INTERVAL"
done
