#!/usr/bin/env bash
# -------------------------------------------------------------------------
# power_usage.sh — Enhanced GUI Battery & Process Monitor (kdialog Version)
# -------------------------------------------------------------------------

LOCK_FILE="/tmp/power_usage_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

# Clean up lock file and close any open kdialogs on exit
cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    pkill -f "kdialog --title Power" 2>/dev/null
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

LOG_FILE="$HOME/scriptlogs/power_usage.log"
INTERVAL=2700  # 45 Minutes

# Power estimation constants (Fallback if sysfs power_now is missing)
CPU_POWER_IDLE=2.0
CPU_POWER_PER_CORE=4.0
MEM_POWER_PER_GB=0.5

# Battery Thresholds
LOW_BATTERY=20
CRITICAL_BATTERY=10

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

get_battery_info() {
    local bat
    bat=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
    [[ -z "$bat" ]] && { echo "No Battery Found"; return 1; }

    local cap=$(cat "$bat/capacity" 2>/dev/null || echo "0")
    local stat=$(cat "$bat/status" 2>/dev/null || echo "Unknown")

    local p_now_uw=$(cat "$bat/power_now" 2>/dev/null || echo "0")
    local v_now_uv=$(cat "$bat/voltage_now" 2>/dev/null || echo "0")
    local c_now_ua=$(cat "$bat/current_now" 2>/dev/null || echo "0")

    local real_watts=0
    if [[ "$p_now_uw" -gt 0 ]]; then
        real_watts=$(safe_bc "$p_now_uw / 1000000")
    elif [[ "$c_now_ua" -gt 0 && "$v_now_uv" -gt 0 ]]; then
        real_watts=$(safe_bc "($c_now_ua * $v_now_uv) / 1000000000000")
    fi

    local e_now_uwh=$(cat "$bat/energy_now" 2>/dev/null || echo "0")
    local c_now_uah=$(cat "$bat/charge_now" 2>/dev/null || echo "0")
    
    local Wh_remaining=0
    if [[ "$e_now_uwh" -gt 0 ]]; then
        Wh_remaining=$(safe_bc "$e_now_uwh / 1000000")
    else
        Wh_remaining=$(safe_bc "($c_now_uah * $v_now_uv) / 1000000000000")
    fi

    local time_str="N/A"
    if [[ $(echo "$real_watts > 0.5" | bc -l) -eq 1 && "$stat" == "Discharging" ]]; then
        local hours_left=$(safe_bc "$Wh_remaining / $real_watts")
        local h=$(echo "$hours_left / 1" | bc)
        local m=$(echo "($hours_left - $h) * 60 / 1" | bc)
        time_str=$(printf "%02dh %02dm" "$h" "$m")
    elif [[ "$stat" == "Charging" ]]; then
        time_str="Charging..."
    else
        time_str="Stationary"
    fi

    echo -e "State: $stat\nLevel: ${cap}%\nLive Draw: ${real_watts}W\nEst. Time: $time_str"
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
    local est_power=$(safe_bc "$CPU_POWER_IDLE + ($avg_cpu / 100) * $CPU_CORES * $CPU_POWER_PER_CORE + ($avg_mem / 100) * $TOTAL_RAM_GB * $MEM_POWER_PER_GB")
    local now=$(date +%s)
    local elapsed=$((now - PREV_TIMESTAMP))
    local energy_interval_kwh=$(safe_bc "$est_power * ($elapsed / 3600) / 1000")
    CUMULATIVE_ENERGY_KWH=$(safe_bc "$CUMULATIVE_ENERGY_KWH + $energy_interval_kwh")
    PREV_TIMESTAMP=$now
    echo "$avg_cpu|$avg_mem|$est_power|$energy_interval_kwh|$CUMULATIVE_ENERGY_KWH"
}

get_top_processes() {
    # Using Tabs (\t) for flexible alignment in kdialog variable-width fonts
    echo -e "PID\tCOMMAND\t%CPU\t%MEM"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6 | tail -n +2 | while read -r p c cpu mem; do
        # Truncate command to 15 chars to keep tabs predictable
        local short_c="${c:0:15}"
        echo -e "$p\t$short_c\t$cpu\t$mem"
    done
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    get_system_info
    sleep 2

    while true; do
        # 1. Close any previous Power Usage dialogs to prevent stacking
        pkill -f "kdialog --title Power" 2>/dev/null

        # 2. Gather Data
        bat_out=$(get_battery_info)
        current_cap=$(echo "$bat_out" | grep "Level:" | grep -oP '\d+' | head -1)
        
        power_data=$(get_process_power_consumption)
        IFS='|' read -r cpu mem pwr_w int_kwh cum_kwh <<< "$power_data"
        top_p=$(get_top_processes)

        # 3. Format Summary
        summary="==============================
  🔋 POWER STATUS: $(date '+%H:%M:%S')
==============================
$bat_out

💻 LOAD: CPU: $cpu% | MEM: $mem%
Est. Load Power: ${pwr_w}W
Interval Energy: ${int_kwh}kWh

🔝 TOP PROCESSES:
$top_p
=============================="

        # 4. Save to Log
        echo -e "$summary" >> "$LOG_FILE"

        # 5. Launch kdialog based on battery health
        if [ "$current_cap" -le "$CRITICAL_BATTERY" ]; then
            kdialog --title "Power: CRITICAL ${current_cap}%" --error "$summary\n\nPLUG IN NOW!" &
        elif [ "$current_cap" -le "$LOW_BATTERY" ]; then
            kdialog --title "Power: LOW ${current_cap}%" --sorry "$summary" &
        else
            kdialog --title "Power Usage Monitor" --msgbox "$summary" &
        fi

        # 6. Wait for next interval
        sleep "$INTERVAL"
    done
}

main
