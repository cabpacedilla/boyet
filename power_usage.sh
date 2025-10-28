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

    local capacity voltage_now voltage_min_design status
    local energy_now energy_full
    
    # Try to read from main battery interface first
    capacity=$(cat "$battery_path/capacity" 2>/dev/null || echo "0")
    voltage_now=$(cat "$battery_path/voltage_now" 2>/dev/null || echo "0")
    voltage_min_design=$(cat "$battery_path/voltage_min_design" 2>/dev/null || echo "0")
    status=$(cat "$battery_path/status" 2>/dev/null || echo "Unknown")
    
    # If voltage_now is empty, try the hwmon2 interface
    if [[ -z "$voltage_now" || "$voltage_now" == "0" ]]; then
        voltage_now=$(cat "$battery_path/hwmon2/in0_input" 2>/dev/null || echo "0")
        # Convert from mV to μV if needed (hwmon usually provides mV)
        if [[ $voltage_now -gt 10000 ]]; then  # If it's in mV (typical 12000-17000 range)
            voltage_now=$((voltage_now * 1000))
        fi
    fi
    
    # Try to get current from hwmon2
    local current_now
    current_now=$(cat "$battery_path/hwmon2/curr1_input" 2>/dev/null || echo "0")
    # Convert from mA to μA if needed
    if [[ $current_now -gt 0 && $current_now -lt 100000 ]]; then
        current_now=$((current_now * 1000))
    fi
    
    # If we have capacity but no voltage_min_design, use a typical value
    if [[ $voltage_min_design -eq 0 && $voltage_now -gt 0 ]]; then
        voltage_min_design=$voltage_now
    elif [[ $voltage_min_design -eq 0 ]]; then
        # Fallback to typical laptop battery voltage (11.1V-14.8V range)
        voltage_min_design=11100000  # 11.1V in μV
    fi
    
    # Calculate energy values
    local energy_now_kwh energy_full_kwh
    
    if [[ $capacity -gt 0 && $voltage_min_design -gt 0 ]]; then
        # Estimate based on capacity percentage and design voltage
        # Typical laptop battery: 40-80 Wh (0.040-0.080 kWh)
        # Using a reasonable estimate - adjust BATTERY_DESIGN_WH as needed
        local BATTERY_DESIGN_WH=60  # 60 Watt-hours is typical for many laptops
        
        energy_full_kwh=$(safe_bc "$BATTERY_DESIGN_WH / 1000")
        energy_now_kwh=$(safe_bc "$energy_full_kwh * $capacity / 100")
        
        echo -e "State: $status\nRemaining Energy: $(printf '%.3f' "$energy_now_kwh") kWh\nFull Capacity: $(printf '%.3f' "$energy_full_kwh") kWh\nBattery Level: ${capacity}%"
    else
        # Fallback: use simplified calculation if we have voltage and current
        if [[ $voltage_now -gt 0 ]]; then
            # Very rough estimate - typical laptop battery capacity
            energy_full_kwh=0.060  # 60 Wh
            if [[ $capacity -gt 0 ]]; then
                energy_now_kwh=$(safe_bc "$energy_full_kwh * $capacity / 100")
            else
                energy_now_kwh=$energy_full_kwh
            fi
            
            echo -e "State: $status\nRemaining Energy: ~$(printf '%.3f' "$energy_now_kwh") kWh\nFull Capacity: ~$(printf '%.3f' "$energy_full_kwh") kWh\nBattery Level: ${capacity}% (estimated)"
        else
            echo "State: $status"
            echo "Battery Level: ${capacity}%"
            echo "Note: Detailed energy information not available"
        fi
    fi
    
    return 0
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
                    "$term" -e bash -c "echo -e \"\$0\"; read -p $'\\nPress Enter to close...'" "$message" &
                    ;;
                gnome-terminal|xfce4-terminal|mate-terminal)
                    "$term" -e bash -c "echo -e \"\$0\"; read -p $'\\nPress Enter to close...'" "$message" &
                    ;;
                *)
                    "$term" -e bash -c "echo -e \"\$0\"; read -p $'\\nPress Enter to close...'" "$message" &
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
