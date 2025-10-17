#!/usr/bin/env bash
# power_usage.sh — Show battery power usage, top processes, and runtime
# Works dynamically on Fedora/Nobara and KDE systems

LOG_FILE="$HOME/scriptlogs/power_usage.log"
INTERVAL=2700  # seconds between readings (45 minutes)
TERMINALS=(konsole gnome-terminal xfce4-terminal tilix lxterminal mate-terminal alacritty urxvt xterm)

# Record script start time
SCRIPT_START=$(date +%s)
mkdir -p "$(dirname "$LOG_FILE")"

# -----------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------

get_battery_info() {
    local battery_path
    battery_path=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
    [[ -z "$battery_path" ]] && { echo "Battery info not found."; return; }

    local state power_source power_now voltage_now
    state=$(cat "$battery_path/status" 2>/dev/null)

    # Detect power source (AC / Battery)
    if [[ -d /sys/class/power_supply/AC ]]; then
        local ac_status
        ac_status=$(cat /sys/class/power_supply/AC/online 2>/dev/null)
        if [[ "$ac_status" == "1" ]]; then
            power_source="AC Adapter"
        else
            power_source="Battery"
        fi
    else
        power_source="Battery"
    fi

    local energy_now_raw energy_full_raw energy_now energy_full divisor unit_detected

    if [[ -f "$battery_path/energy_now" && -f "$battery_path/energy_full" ]]; then
        # Use energy_* directly
        energy_now_raw=$(cat "$battery_path/energy_now")
        energy_full_raw=$(cat "$battery_path/energy_full")
        unit_detected="energy_*"
    else
        # Fallback: derive energy from charge × voltage
        local charge_now charge_full
        charge_now=$(cat "$battery_path/charge_now" 2>/dev/null)
        charge_full=$(cat "$battery_path/charge_full" 2>/dev/null)
        voltage_now=$(cat "$battery_path/voltage_now" 2>/dev/null)
        energy_now_raw=$(echo "$charge_now * $voltage_now" | bc -l)
        energy_full_raw=$(echo "$charge_full * $voltage_now" | bc -l)
        unit_detected="charge_*"
    fi

    # Auto-scale units based on value magnitude
    local max_val
    max_val=$(echo "$energy_full_raw" | cut -d'.' -f1)
    if (( max_val > 1000000000000 )); then
        divisor=1000000000000  # pWh → Wh
    elif (( max_val > 1000000000 )); then
        divisor=1000000000     # nWh → Wh
    elif (( max_val > 1000000 )); then
        divisor=1000000        # µWh → Wh
    elif (( max_val > 1000 )); then
        divisor=1000           # mWh → Wh
    else
        divisor=1
    fi

    energy_now=$(echo "scale=2; $energy_now_raw / $divisor" | bc -l)
    energy_full=$(echo "scale=2; $energy_full_raw / $divisor" | bc -l)
    local percentage
    percentage=$(echo "scale=1; 100 * $energy_now / $energy_full" | bc -l)

    # Detect current power draw
    if [[ -f "$battery_path/power_now" ]]; then
        power_now=$(cat "$battery_path/power_now" 2>/dev/null)
        if (( power_now > 0 )); then
            power_now=$(echo "scale=2; $power_now / 1000000" | bc -l)  # µW → W
        else
            power_now=15
        fi
    else
        power_now=15
    fi

    # Estimate runtime
    local runtime_est
    if (( $(echo "$power_now > 0" | bc -l) )); then
        runtime_est=$(echo "scale=2; $energy_now / $power_now" | bc -l)
    else
        runtime_est="∞"
    fi

    echo -e "Power Source: $power_source"
    echo -e "State: $state"
    echo -e "Battery Level: $(printf '%.0f' "$percentage")%"
    echo -e "Remaining Energy: $(printf '%.2f' "$energy_now") Wh"
    echo -e "Full Capacity: $(printf '%.2f' "$energy_full") Wh"
    echo -e "Est. Runtime: ~$(printf '%.2f' "$runtime_est") hrs (assuming ${power_now}W load)"
    echo -e "(Detected: $unit_detected, divisor=$divisor)"
}

get_top_processes() {
    {
        printf "%-10s %-18s %-8s %-8s\n" "PID" "COMMAND" "%CPU" "%MEM"
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk 'NR>1 && NR<=11 {printf "%-10s %-18s %-8s %-8s\n", $1, $2, $3, $4}'
    } 2>/dev/null
}

launch_terminal() {
    local datetime="$1"
    local elapsed="$2"
    local message="$3"

    for term in "${TERMINALS[@]}"; do
        if command -v "$term" >/dev/null 2>&1; then
            "$term" -e bash -c "echo -e \"Battery Usage Summary - [$datetime] (Elapsed: $elapsed) \n\n$message\"; echo; read -p 'Press Enter to close...'" &
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
