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
TERMINALS=(konsole gnome-terminal xfce4-terminal tilix lxterminal mate-terminal alacritty urxrt xterm)

# Power consumption constants (typical values for estimation)
CPU_POWER_IDLE=2.0        # Watts when idle
CPU_POWER_PER_CORE=4.0    # Additional Watts per core at 100% usage
MEM_POWER_PER_GB=0.5      # Watts per GB of RAM usage

# Record the script start time
SCRIPT_START=$(date +%s)

# Safe bc calculation function
safe_bc() {
    echo "scale=6; $1" | bc -l 2>/dev/null || echo "0"
}

# -----------------------------------------------------------
# SYSTEM INFO
# -----------------------------------------------------------
get_system_info() {
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(safe_bc "$TOTAL_RAM_KB / 1024 / 1024")
    
    # Initialize CPU tracking
    read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    PREV_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    PREV_IDLE=$idle
    PREV_TIMESTAMP=$(date +%s)
}

# -----------------------------------------------------------
# BATTERY INFO
# -----------------------------------------------------------
get_battery_info() {
    local battery_path
    battery_path=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)

    if [[ -z "$battery_path" ]]; then
        echo "Battery info not found in sysfs."
        return 1
    fi

    local charge_now charge_full voltage_now design_voltage state
    charge_now=$(cat "$battery_path/charge_now" 2>/dev/null || echo "0")
    charge_full=$(cat "$battery_path/charge_full" 2>/dev/null || echo "0")
    voltage_now=$(cat "$battery_path/voltage_now" 2>/dev/null || echo "0")
    design_voltage=$(cat "$battery_path/voltage_min_design" 2>/dev/null || cat "$battery_path/voltage_max_design" 2>/dev/null || echo "0")
    state=$(cat "$battery_path/status" 2>/dev/null || echo "Unknown")

    # If design_voltage not available, use current voltage as fallback
    if [[ $design_voltage -eq 0 ]]; then
        design_voltage=$voltage_now
    fi

    # Convert from μWh to kWh (more accurate calculation)
    local energy_now_wh=$(safe_bc "$charge_now * $voltage_now / 1000000")
    local energy_full_wh=$(safe_bc "$charge_full * $design_voltage / 1000000")
    local energy_now_kwh=$(safe_bc "$energy_now_wh / 1000")
    local energy_full_kwh=$(safe_bc "$energy_full_wh / 1000")
    
    # Calculate percentage
    local percentage=0
    if [[ $charge_full -gt 0 ]]; then
        percentage=$(safe_bc "100 * $charge_now / $charge_full")
    fi

    echo -e "State: $state\nRemaining Energy: $(printf '%.3f' "$energy_now_kwh") kWh\nFull Capacity: $(printf '%.3f' "$energy_full_kwh") kWh\nBattery Level: $(printf '%.1f' "$percentage")%"
}

# -----------------------------------------------------------
# Average CPU/MEM Tracking and Energy Accounting
# -----------------------------------------------------------
PREV_TOTAL=0
PREV_IDLE=0
PREV_TIMESTAMP=0
CUMULATIVE_ENERGY_KWH=0  # total energy used since script start

get_average_cpu_usage() {
    read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    if [[ $PREV_TOTAL -ne 0 ]]; then
        local diff_total=$((total - PREV_TOTAL))
        local diff_idle=$((idle - PREV_IDLE))
        local diff_used=$((diff_total - diff_idle))
        local cpu_avg=$(safe_bc "100 * $diff_used / $diff_total")
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
    local mem_percent=$(safe_bc "100 * $mem_used / $mem_total")
    echo "$mem_percent"
}

get_process_power_consumption() {
    local avg_cpu avg_mem
    avg_cpu=$(get_average_cpu_usage)
    avg_mem=$(get_average_mem_usage)

    local cpu_power=$(safe_bc "$CPU_POWER_IDLE + ($avg_cpu / 100) * $CPU_CORES * $CPU_POWER_PER_CORE")
    local mem_power=$(safe_bc "($avg_mem / 100) * $TOTAL_RAM_GB * $MEM_POWER_PER_GB")
    local total_power=$(safe_bc "$cpu_power + $mem_power")

    local now=$(date +%s)
    local elapsed=$((now - PREV_TIMESTAMP))
    local interval_hours=$(safe_bc "$elapsed / 3600")
    local energy_interval_kwh=$(safe_bc "$total_power * $interval_hours / 1000")

    CUMULATIVE_ENERGY_KWH=$(safe_bc "$CUMULATIVE_ENERGY_KWH + $energy_interval_kwh")
    PREV_TIMESTAMP=$now

    echo "$avg_cpu|$avg_mem|$total_power|$energy_interval_kwh|$CUMULATIVE_ENERGY_KWH"
}

get_top_processes() {
    local avg_cpu="$1"
    local avg_mem="$2"
    local total_power="$3"
    
    local interval_hours=$(safe_bc "$INTERVAL / 3600")

    {
        printf "%-8s %-20s %-8s %-8s %-12s\n" "PID" "COMMAND" "%CPU" "%MEM" "kWh_USED"
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 11 | tail -n +2 | \
        while read -r pid comm cpu mem; do
            [[ -z "$pid" ]] && continue
            cpu_power_proc=$(safe_bc "($cpu / 100) * $CPU_CORES * $CPU_POWER_PER_CORE")
            mem_power_proc=$(safe_bc "($mem / 100) * $TOTAL_RAM_GB * $MEM_POWER_PER_GB")
            total_power_proc=$(safe_bc "$cpu_power_proc + $mem_power_proc")
            energy_proc_kwh=$(safe_bc "$total_power_proc * $interval_hours / 1000")
            printf "%-8s %-20s %-8.1f %-8.1f %-12.6f\n" "$pid" "$comm" "$cpu" "$mem" "$energy_proc_kwh"
        done

        printf "\nPower Consumption Summary:\n"
        printf "Averaged CPU Usage: %.2f%%\n" "$avg_cpu"
        printf "Averaged MEM Usage: %.2f%%\n" "$avg_mem"
        printf "Estimated Power Draw: %.2f W\n" "$total_power"
        
        # Get the energy values from the latest calculation
        local power_data
        power_data=$(get_process_power_consumption)
        IFS='|' read -r current_cpu current_mem current_power energy_interval_kwh cumulative_kwh <<< "$power_data"
        
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
            case "$term" in
                konsole|tilix|alacritty)
                    "$term" -e bash -c "echo -e \"\$0\"; read -p 'Press Enter to close...'" "$message" &
                    ;;
                gnome-terminal|xfce4-terminal|mate-terminal)
                    "$term" -- bash -c "echo -e \"\$0\"; read -p 'Press Enter to close...'" "$message" &
                    ;;
                *)
                    "$term" -e bash -c "echo -e \"\$0\"; read -p 'Press Enter to close...'" "$message" &
                    ;;
            esac
            return
        fi
    done

    notify-send "⚠️ Power Usage Alert" "No supported terminal emulator found to display results."
}

# -----------------------------------------------------------
# LOGGING SETUP
# -----------------------------------------------------------
setup_logging() {
    local log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "Error: Cannot create log directory $log_dir"
            exit 1
        }
    fi
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE" || {
        echo "Error: Cannot create log file $LOG_FILE"
        exit 1
    }
}

# -----------------------------------------------------------
# MAIN LOOP
# -----------------------------------------------------------
main() {
    setup_logging
    get_system_info

    notify-send "🔋 Power Usage Monitor Started" "Interval: $((INTERVAL / 60)) minutes."
    echo "[$(date)] Power usage monitor started (interval: $INTERVAL seconds)." >> "$LOG_FILE"
    echo "System Info: $CPU_CORES CPU cores, ${TOTAL_RAM_GB}GB RAM" >> "$LOG_FILE"

    # Initial sleep to get proper CPU delta
    sleep 5

    while true; do
        datetime="$(date '+%a %d %b %Y %T %Z')"
        now=$(date +%s)
        elapsed_sec=$((now - SCRIPT_START))
        elapsed_min=$((elapsed_sec / 60))
        elapsed_hr=$((elapsed_min / 60))
        elapsed_fmt="$(printf '%02dh %02dm' $elapsed_hr $((elapsed_min % 60)))"

        battery_info=$(get_battery_info)
        
        # Get power data ONCE and extract values
        power_data=$(get_process_power_consumption)
        IFS='|' read -r avg_cpu avg_mem total_power energy_interval_kwh cumulative_kwh <<< "$power_data"
        
        # Pass the already calculated values to get_top_processes
        top_procs=$(get_top_processes "$avg_cpu" "$avg_mem" "$total_power")
        
        summary="🔋 Power Stats:\n$battery_info\n\n⚙ Top Processes & Power Consumption:\n$top_procs"

        echo -e "\n[$datetime] (Elapsed: $elapsed_fmt)\n$summary" >> "$LOG_FILE"
        notify-send "🔋 Battery Usage Summary" "Recorded at $datetime. Elapsed: $elapsed_fmt"
        launch_terminal "$datetime" "$elapsed_fmt" "$summary"
        
        sleep "$INTERVAL"
    done
}

# Handle script interruption
cleanup() {
    echo "[$(date)] Power usage monitor stopped." >> "$LOG_FILE"
    notify-send "🔋 Power Usage Monitor" "Monitoring stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Run main function
main
