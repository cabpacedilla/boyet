#!/usr/bin/env bash
# Low Memory Alert Script (Robust + Diagnostic)
# Works on any Linux distro, detects swapping, tracks per-process memory growth

LOCK_FILE="/tmp/lowMemAlert_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

MEMFREE_LIMIT_PERCENT=5
CHECK_INTERVAL=5
MAX_PROCESSES=10
LOG_FILE="$HOME/lowmem_alert.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))   # 50 MB

# -----------------------------
# Core detection: Get memory stats robustly
# -----------------------------
get_memory_stats() {
    if command -v free >/dev/null 2>&1; then
        read TOTAL_MEM MEMFREE < <(free -m | awk 'NR==2 {print $2, $7}')
    elif [ -r /proc/meminfo ]; then
        TOTAL_MEM=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
        MEMFREE=$(awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
    else
        echo "Error: Cannot determine memory stats." >&2
        exit 1
    fi
}

# -----------------------------
# Diagnostics: Swap detection
# -----------------------------
detect_swap_activity() {
    SWAP_USED=$(awk '/SwapTotal:/ {total=$2} /SwapFree:/ {free=$2} END{print int((total-free)/1024)}' /proc/meminfo)
    SWAP_TOTAL=$(awk '/SwapTotal:/ {print int($2/1024)}' /proc/meminfo)
}

# -----------------------------
# Diagnostics: Per-process memory growth
# -----------------------------
track_process_memory_growth() {
    PROC_MEM_FILE="$HOME/.proc_mem_usage"
    ps -eo pid,comm,rss --no-headers | sort -k3 -nr > /tmp/current_mem_usage

    if [ -f "$PROC_MEM_FILE" ]; then
        echo "Memory growth since last check:"
        join -1 1 -2 1 <(sort /tmp/current_mem_usage) "$PROC_MEM_FILE" | \
            awk '{growth=$3-$4; if(growth>0) printf "%s (%s): +%.1f MB\n",$2,$1,growth/1024}'
    fi

    cp /tmp/current_mem_usage "$PROC_MEM_FILE"
}

# -----------------------------
# Top memory consumers
# -----------------------------
get_top_processes() {
    ps -eo pid,comm,%mem,rss --sort=-%mem --no-headers | head -n "$MAX_PROCESSES" | \
        awk '{size_mb=$4/1024; size_str=(size_mb>=1024)?sprintf("%.1f GB",size_mb/1024):sprintf("%.0f MB",size_mb);
              printf "PID %s (%s): %.2f%% (%s)\n",$1,$2,$3,size_str}'
}

# -----------------------------
# Log rotation
# -----------------------------
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(stat -c%s "$LOG_FILE")
        if [ "$LOG_SIZE" -ge "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d%H%M%S).bak"
            touch "$LOG_FILE"
        fi
    fi
}

# -----------------------------
# Notification
# -----------------------------
send_notification() {
    local msg="$1"
    notify-send -u critical "⚠ Low Memory Alert" "$msg"
}

# -----------------------------
# Main loop
# -----------------------------
while true; do
    get_memory_stats
    detect_swap_activity

    THRESHOLD=$(( TOTAL_MEM * MEMFREE_LIMIT_PERCENT / 100 ))

    if [[ "$MEMFREE" =~ ^[0-9]+$ ]] && [ "$MEMFREE" -le "$THRESHOLD" ]; then
        TOP_PROCESSES=$(get_top_processes)
        track_process_memory_growth

        NOTIF="$(date '+%H:%M:%S')
Total RAM: ${TOTAL_MEM} MB
Available: ${MEMFREE} MB (Threshold: ${THRESHOLD} MB)
Swap used: ${SWAP_USED} MB / ${SWAP_TOTAL} MB

Top memory consumers:
$TOP_PROCESSES"

        echo "[$(date)] $NOTIF" >> "$LOG_FILE"
        rotate_log
        send_notification "$NOTIF"
    fi

    sleep "$CHECK_INTERVAL"
done
