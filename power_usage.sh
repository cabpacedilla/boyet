#!/usr/bin/env bash
# power_usage.sh — Show battery power usage, top processes, and runtime
# Works dynamically on Fedora/Nobara and KDE systems

LOG_FILE="$HOME/scriptlogs/power_usage.log"
INTERVAL=2700  # seconds between readings
TERMINALS=(konsole gnome-terminal xfce4-terminal tilix lxterminal mate-terminal alacritty urxvt xterm)

# Record the script start time
SCRIPT_START=$(date +%s)

# -----------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------

get_battery_info() {
    local battery_path
    battery_path=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)

    if [[ -z "$battery_path" ]]; then
        echo "Battery info not found in sysfs."
        return
    fi

    local charge_now charge_full voltage_now state
    charge_now=$(cat "$battery_path/charge_now" 2>/dev/null)
    charge_full=$(cat "$battery_path/charge_full" 2>/dev/null)
    voltage_now=$(cat "$battery_path/voltage_now" 2>/dev/null)
    state=$(cat "$battery_path/status" 2>/dev/null)

    if [[ -z "$charge_now" || -z "$charge_full" || -z "$voltage_now" ]]; then
        echo "Incomplete battery data."
        return
    fi

    # Convert charge to Wh
    local energy_now_wh=$(echo "$charge_now * $voltage_now / 1000000" | bc -l)
    local energy_full_wh=$(echo "$charge_full * $voltage_now / 1000000" | bc -l)
    local percentage=$(echo "scale=1; 100 * $charge_now / $charge_full" | bc -l)

    echo -e "State: $state\nRemaining Energy: $(printf '%.2f' "$energy_now_wh") Wh\nFull Capacity: $(printf '%.2f' "$energy_full_wh") Wh\nBattery Level: $(printf '%.0f' "$percentage")%"
}

get_top_processes() {
    # Use ps and format columns with consistent width
    {
        printf "%-12s %-20s %-10s %-10s\n" "PID" "COMMAND" "%CPU" "%MEM"
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 11 | tail -n +2 | \
        awk '{printf "%-12s %-20s %-10s %-10s\n", $1, $2, $3, $4}'
    }
}

launch_terminal() {
    local datetime="$1"
    local elapsed="$2"
    local message="$3"

    for term in "${TERMINALS[@]}"; do
        if command -v "$term" >/dev/null 2>&1; then
            "$term" -e bash -c "echo -e \"Battery Usage Summary - [$datetime] (Elapsed: $elapsed)\n\n$message\n\"; read -p 'Press Enter to close...'" &
            return
        fi
    done

    notify-send "⚠️ Power Usage Alert" "No supported terminal emulator found to display results."
}

# -----------------------------------------------------------
# MAIN LOOP
# -----------------------------------------------------------

notify-send "🔋 Power Usage Monitor Started" "Interval: $((INTERVAL / 60)) minutes."
echo "[$(date)] Power usage monitor started (interval: $INTERVAL seconds)." >> "$LOG_FILE"

while true; do
    sleep "$INTERVAL"

    datetime="$(date '+%a %d %b %Y %T %Z')"
    now=$(date +%s)
    elapsed_sec=$((now - SCRIPT_START))
    elapsed_min=$((elapsed_sec / 60))
    elapsed_hr=$((elapsed_min / 60))
    elapsed_fmt="$(printf '%02dh %02dm' $elapsed_hr $((elapsed_min % 60)))"

    battery_info=$(get_battery_info)
    top_procs=$(get_top_processes)
    summary="🔋 Power Stats:\n$battery_info\n\n⚙ Top Processes:\n$top_procs"

    echo -e "\n[$datetime] (Elapsed: $elapsed_fmt)\n$summary\n" >> "$LOG_FILE"
    notify-send "🔋 Battery Usage Summary" "Recorded at $datetime. Elapsed: $elapsed_fmt"
    launch_terminal "$datetime" "$elapsed_fmt" "$summary"
done
