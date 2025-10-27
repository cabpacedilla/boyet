#!/usr/bin/env bash
# -----------------------------------------------------------
# power_usage.sh — Battery & Power Usage Monitor
# -----------------------------------------------------------
# Shows averaged CPU/MEM usage, per-process power estimates,
# and cumulative energy consumption over time.
# Works dynamically on Fedora/Nobara and KDE systems.
# -----------------------------------------------------------

LOG_FILE="$HOME/scriptlogs/power_usage.log"
INTERVAL=2700  # seconds between readings (default: 45 minutes)
TERMINALS=(konsole gnome-terminal xfce4-terminal tilix lxterminal mate-terminal alacritty urxvt xterm)

# Power consumption constants (typical values for estimation)
CPU_POWER_IDLE=2.0        # Watts when idle
CPU_POWER_PER_CORE=4.0    # Additional Watts per core at 100% usage
MEM_POWER_PER_GB=0.5      # Watts per GB of RAM usage

# Record the script start time
SCRIPT_START=$(date +%s)

# -----------------------------------------------------------
# SYSTEM INFO
# -----------------------------------------------------------
get_system_info() {
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM_KB / 1024 / 1024" | bc -l 2>/dev/null || echo "8.00")
}

# -----------------------------------------------------------
# BATTERY INFO
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

    local energy_now_wh=$(echo "$charge_now * $voltage_now / 1000000000000" | bc -l 2>/dev/null || echo "0")
    local energy_full_wh=$(echo "$charge_full * $voltage_now / 1000000000000" | bc -l 2>/dev/null || echo "0")
    local energy_now_kwh=$(echo "$energy_now_wh / 1000" | bc -l 2>/dev/null || echo "0")
    local energy_full_kwh=$(echo "$energy_full_wh / 1000" | bc -l 2>/dev/null || echo "0")
    local percentage=$(echo "scale=1; 100 * $charge_now / $charge_full" | bc -l 2>/dev/null || echo "0")

    echo -e "State: $state\nRemaining Energy: $(printf '%.3f' "$energy_now_kwh") kWh\nFull Capacity: $(printf '%.3f' "$energy_full_kwh") kWh\nBattery Level: $(printf '%.0f' "$percentage")%"
}

# -----------------------------------------------------------
# Average CPU/MEM Tracking and Energy Accounting
# -----------------------------------------------------------
PREV_TOTAL=0
PREV_IDLE=0
PREV_TIMESTAMP=$(date +%s)
CUMULATIVE_ENERGY_KWH=0  # total energy used since script start

get_average_cpu_usage() {
    read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    if [[ $PREV_TOTAL -ne 0 ]]; then
        local diff_total=$((total - PREV_TOTAL))
        local diff_idle=$((idle - PREV_IDLE))
        local diff_used=$((diff_total - diff_idle))
        local cpu_avg=$(echo "scale=2; 100 * $diff_used / $diff_total" | bc -l)
        echo "$cpu_avg"
    else
        echo "0"
    fi

    PREV_TOTAL=$total
    PREV_IDLE=$idle
}

get_average_mem_usage() {
    local mem_total mem_available
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local mem_used=$((mem_total - mem_available))
    local mem_percent=$(echo "scale=2; 100 * $mem_used / $mem_total" | bc -l)
    echo "$mem_percent"
}

get_process_power_consumption() {
    local avg_cpu avg_mem
    avg_cpu=$(get_average_cpu_usage)
    avg_mem=$(get_average_mem_usage)

    local cpu_power=$(echo "$CPU_POWER_IDLE + ($avg_cpu / 100) * $CPU_CORES * $CPU_POWER_PER_CORE" | bc -l)
    local mem_power=$(echo "($avg_mem / 100) * $TOTAL_RAM_GB * $MEM_POWER_PER_GB" | bc -l)
    local total_power=$(echo "$cpu_power + $mem_power" | bc -l)

    local now=$(date +%s)
    local elapsed=$((now - PREV_TIMESTAMP))
    local interval_hours=$(echo "$elapsed / 3600" | bc -l)
    local energy_interval_kwh=$(echo "$total_power * $interval_hours / 1000" | bc -l)

    CUMULATIVE_ENERGY_KWH=$(echo "$CUMULATIVE_ENERGY_KWH + $energy_interval_kwh" | bc -l)
    PREV_TIMESTAMP=$now

    echo "$avg_cpu|$avg_mem|$total_power|$energy_interval_kwh|$CUMULATIVE_ENERGY_KWH"
}

get_top_processes() {
    local power_data
    power_data=$(get_process_power_consumption)
    IFS='|' read -r avg_cpu avg_mem total_power energy_interval_kwh cumulative_kwh <<< "$power_data"

    local interval_hours
    interval_hours=$(echo "$INTERVAL / 3600" | bc -l 2>/dev/null || echo "0")

    {
        printf "%-8s %-20s %-8s %-8s %-12s\n" "PID" "COMMAND" "%CPU" "%MEM" "kWh_USED"
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 11 | tail -n +2 | \
        while read pid comm cpu mem; do
            cpu_power_proc=$(echo "($cpu / 100) * $CPU_CORES * $CPU_POWER_PER_CORE" | bc -l)
            mem_power_proc=$(echo "($mem / 100) * $TOTAL_RAM_GB * $MEM_POWER_PER_GB" | bc -l)
            total_power_proc=$(echo "$cpu_power_proc + $mem_power_proc" | bc -l)
            energy_proc_kwh=$(echo "$total_power_proc * $interval_hours / 1000" | bc -l)
            printf "%-8s %-20s %-8.1f %-8.1f %-12.6f\n" "$pid" "$comm" "$cpu" "$mem" "$energy_proc_kwh"
        done

        printf "\nPower Consumption Summary:\n"
        printf "Averaged CPU Usage: %.2f%%\n" "$avg_cpu"
        printf "Averaged MEM Usage: %.2f%%\n" "$avg_mem"
        printf "Estimated Power Draw: %.2f W\n" "$total_power"
        printf "Energy Used (Interval): %.6f kWh\n" "$energy_interval_kwh"
        printf "Cumulative Energy Used: %.6f kWh\n" "$cumulative_kwh"
    }
}

# -----------------------------------------------------------
# TERMINAL OUTPUT
# -----------------------------------------------------------
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
get_system_info

notify-send "🔋 Power Usage Monitor Started" "Interval: $((INTERVAL / 60)) minutes."
echo "[$(date)] Power usage monitor started (interval: $INTERVAL seconds)." >> "$LOG_FILE"
echo "System Info: $CPU_CORES CPU cores, ${TOTAL_RAM_GB}GB RAM" >> "$LOG_FILE"

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
    summary="🔋 Power Stats:\n$battery_info\n\n⚙ Top Processes & Power Consumption:\n$top_procs"

    echo -e "\n[$datetime] (Elapsed: $elapsed_fmt)\n$summary\n" >> "$LOG_FILE"
    notify-send "🔋 Battery Usage Summary" "Recorded at $datetime. Elapsed: $elapsed_fmt"
    launch_terminal "$datetime" "$elapsed_fmt" "$summary"
done
