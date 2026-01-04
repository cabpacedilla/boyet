#!/usr/bin/env bash
# -----------------------------------------------------------
# power_usage.sh — Enhanced Battery & Time Estimation Monitor
# -----------------------------------------------------------

LOG_FILE="$HOME/scriptlogs/power_usage.log"
INTERVAL=2700  
TERMINALS=(konsole gnome-terminal xfce4-terminal tilix lxterminal mate-terminal alacritty urxrt xterm)

# Power estimation constants (Fallback if sysfs power_now is missing)
CPU_POWER_IDLE=2.0
CPU_POWER_PER_CORE=4.0
MEM_POWER_PER_GB=0.5

SCRIPT_START=$(date +%s)
CUMULATIVE_ENERGY_KWH=0

safe_bc() {
    echo "scale=6; $1" | bc -l 2>/dev/null || echo "0"
}

get_system_info() {
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(safe_bc "$TOTAL_RAM_KB / 1024 / 1024")
    
    # Init CPU tracking
    read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    PREV_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    PREV_IDLE=$idle
    PREV_TIMESTAMP=$(date +%s)
}

# -----------------------------------------------------------
# IMPROVED BATTERY & TIME ESTIMATION
# -----------------------------------------------------------
get_battery_info() {
    local bat
    bat=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
    [[ -z "$bat" ]] && { echo "No Battery Found"; return 1; }

    # 1. Get capacity and status
    local cap=$(cat "$bat/capacity" 2>/dev/null || echo "0")
    local stat=$(cat "$bat/status" 2>/dev/null || echo "Unknown")

    # 2. Get Power Draw (W) - Hardware level
    # Some laptops use power_now (uW), others use current_now (uA) * voltage_now (uV)
    local p_now_uw=$(cat "$bat/power_now" 2>/dev/null || echo "0")
    local v_now_uv=$(cat "$bat/voltage_now" 2>/dev/null || echo "0")
    local c_now_ua=$(cat "$bat/current_now" 2>/dev/null || echo "0")

    local real_watts=0
    if [[ "$p_now_uw" -gt 0 ]]; then
        real_watts=$(safe_bc "$p_now_uw / 1000000")
    elif [[ "$c_now_ua" -gt 0 && "$v_now_uv" -gt 0 ]]; then
        real_watts=$(safe_bc "($c_now_ua * $v_now_uv) / 1000000000000")
    fi

    # 3. Get Energy Remaining (Wh)
    # energy_now (uWh) or charge_now (uAh) * voltage
    local e_now_uwh=$(cat "$bat/energy_now" 2>/dev/null || echo "0")
    local c_now_uah=$(cat "$bat/charge_now" 2>/dev/null || echo "0")
    
    local Wh_remaining=0
    if [[ "$e_now_uwh" -gt 0 ]]; then
        Wh_remaining=$(safe_bc "$e_now_uwh / 1000000")
    else
        Wh_remaining=$(safe_bc "($c_now_uah * $v_now_uv) / 1000000000000")
    fi

    # 4. Calculate Time Remaining
    local time_str="N/A"
    if [[ $(echo "$real_watts > 0.5" | bc -l) -eq 1 && "$stat" == "Discharging" ]]; then
        local hours_left=$(safe_bc "$Wh_remaining / $real_watts")
        local h=$(echo "$hours_left / 1" | bc)
        local m=$(echo "($hours_left - $h) * 60 / 1" | bc)
        time_str=$(printf "%02dh %02dm" "$h" "$m")
    elif [[ "$stat" == "Charging" ]]; then
        time_str="Charging..."
    else
        time_str="Infinite/Stationary"
    fi

    echo -e "State: $stat\nLevel: ${cap}%\nLive Draw: ${real_watts}W\nEst. Time Remaining: $time_str"
    
    # Return metrics for log consumption
    echo "$real_watts|$Wh_remaining|$stat" > /tmp/bat_metrics
}

get_average_cpu_usage() {
    read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local diff_total=$((total - PREV_TOTAL))
    local diff_idle=$((idle - PREV_IDLE))
    local cpu_avg=$(safe_bc "100 * ($diff_total - $diff_idle) / $diff_total")
    PREV_TOTAL=$total; PREV_IDLE=$idle
    echo "$cpu_avg"
}

get_average_mem_usage() {
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    echo $(safe_bc "100 * ($mem_total - $mem_available) / $mem_total")
}

get_process_power_consumption() {
    local avg_cpu=$(get_average_cpu_usage)
    local avg_mem=$(get_average_mem_usage)

    # Estimate based on load
    local est_power=$(safe_bc "$CPU_POWER_IDLE + ($avg_cpu / 100) * $CPU_CORES * $CPU_POWER_PER_CORE + ($avg_mem / 100) * $TOTAL_RAM_GB * $MEM_POWER_PER_GB")

    local now=$(date +%s)
    local elapsed=$((now - PREV_TIMESTAMP))
    local energy_interval_kwh=$(safe_bc "$est_power * ($elapsed / 3600) / 1000")
    CUMULATIVE_ENERGY_KWH=$(safe_bc "$CUMULATIVE_ENERGY_KWH + $energy_interval_kwh")
    PREV_TIMESTAMP=$now

    echo "$avg_cpu|$avg_mem|$est_power|$energy_interval_kwh|$CUMULATIVE_ENERGY_KWH"
}

get_top_processes() {
    # Define fixed widths for clean vertical alignment
    local w_pid=10
    local w_comm=20
    local w_cpu=10
    local w_mem=10

    # Print Headers (Left-aligned)
    printf "%-${w_pid}s %-${w_comm}s %-${w_cpu}s %-${w_mem}s\n" "PID" "COMMAND" "%CPU" "%MEM"

    # Process and align each row of data
    # Using 'comm' for the command ensures names don't have spaces that break alignment
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6 | tail -n +2 | while read -r p c cpu mem; do
        printf "%-${w_pid}s %-${w_comm}s %-${w_cpu}s %-${w_mem}s\n" "$p" "$c" "$cpu" "$mem"
    done
}

launch_terminal() {
    local msg="$1"
    for term in "${TERMINALS[@]}"; do
        if command -v "$term" >/dev/null 2>&1; then
            # We wrap the logic in a clean subshell that handles its own exit
            "$term" -e bash -c "
                trap 'exit' INT TERM
                echo -e \"$msg\"
                echo -e \"\n\"
                read -n 1 -s -r -p \"Press any key to close...\"
                exit
            " & 
            return
        fi
    done
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    get_system_info
    sleep 2

    while true; do
        bat_out=$(get_battery_info)
        power_data=$(get_process_power_consumption)
        IFS='|' read -r cpu mem pwr_w int_kwh cum_kwh <<< "$power_data"
        top_p=$(get_top_processes)

        summary="--- POWER REPORT $(date '+%H:%M:%S') ---\n$bat_out\n\nCPU: $cpu% | MEM: $mem%\nLoad-Est Power: ${pwr_w}W\nInterval Energy: ${int_kwh}kWh\n\n$top_p"

        echo -e "$summary" >> "$LOG_FILE"
        launch_terminal "$summary"
        sleep "$INTERVAL"
    done
}

main
