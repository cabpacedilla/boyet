#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# System Collapse Monitor - Only Detect When System is Going Down
# -----------------------------------------------------------------------------
# Only alerts when system is experiencing or about to experience complete
# performance collapse - "on its knees" scenarios.
# -----------------------------------------------------------------------------

# -----------------------------
# Collapse Threshold Configuration
# -----------------------------------------------------------------------------
# These thresholds indicate the system is truly failing, not just stressed

# Memory Collapse - System freezing due to memory exhaustion
MEMFREE_COLLAPSE_PERCENT=2
MEMFREE_COLLAPSE_ABSOLUTE_MB=128
SWAP_COLLAPSE_PERCENT=90           # Heavy swap thrashing
MEM_PRESSURE_COLLAPSE=35.0         # Severe memory pressure

# CPU Collapse - System unresponsive due to CPU exhaustion  
LOAD_COLLAPSE_PERCENT=200          # Load > 2x CPU cores = saturation
IO_WAIT_COLLAPSE=25.0              # Extreme I/O bottleneck
CPU_IDLE_COLLAPSE=2.0              # Virtually no CPU available

# Combination Collapse - Multiple parameters causing system failure
MEMORY_SWAP_COLLAPSE=1             # Memory exhausted + heavy swapping
CPU_IO_COLLAPSE=2                  # CPU saturated + I/O blocked
MEMORY_PRESSURE_SWAP_COLLAPSE=3    # Severe pressure + swap thrashing
COMPLETE_COLLAPSE=4                # Multiple collapse conditions

CHECK_INTERVAL=30
LOG_FILE="$HOME/system_collapse.log"
ALERT_COOLDOWN=600  # 10 minutes between collapse alerts

# -----------------------------
# Globals
# -----------------------------
LAST_OOM_CHECK=$(date +%s)
LAST_ALERT_TIME=0
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)

# -----------------------------
# Logging and Setup
# -----------------------------
init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
}

log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

rotate_logs() {
    local max_size_kb=5120
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        local size_kb
        size_kb=$(du -k "$LOG_FILE" | cut -f1)
        if [ "$size_kb" -gt "$max_size_kb" ]; then
            mv "$LOG_FILE" "$LOG_FILE.$(date +%s).bak"
            log "Log rotated (size > ${max_size_kb}KB)"
        fi
    fi
}

# -----------------------------
# Metric Collection
# -----------------------------
get_memory_metrics() {
    local mem_total mem_avail swap_total swap_free
    mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    swap_total=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
    
    local mem_percent_free swap_percent_used
    if [ "$mem_total" -gt 0 ]; then
        mem_percent_free=$(echo "scale=2; $mem_avail * 100 / $mem_total" | bc)
    else
        mem_percent_free=100
    fi

    if [ "$swap_total" -gt 0 ]; then
        local swap_used=$((swap_total - swap_free))
        swap_percent_used=$(echo "scale=2; $swap_used * 100 / $swap_total" | bc)
    else
        swap_percent_used=0
    fi

    echo "$mem_percent_free $swap_percent_used $mem_avail $swap_total"
}

get_cpu_metrics() {
    # Get load averages
    read -r load1 load5 load15 _ < /proc/loadavg
    
    # Get CPU utilization from /proc/stat - more robust parsing
    local cpu_line
    cpu_line=$(grep '^cpu ' /proc/stat)
    
    # Extract all CPU fields safely
    local user nice system idle iowait irq softirq steal guest guest_nice
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice <<< "$cpu_line"
    
    # Handle case where some fields might be missing by providing defaults
    user=${user:-0}; nice=${nice:-0}; system=${system:-0}; idle=${idle:-0}
    iowait=${iowait:-0}; irq=${irq:-0}; softirq=${softirq:-0}; steal=${steal:-0}
    
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    
    # Avoid division by zero and handle empty values
    if [ "$total" -gt 0 ]; then
        cpu_idle=$(echo "scale=2; $idle * 100 / $total" | bc)
        io_wait=$(echo "scale=2; $iowait * 100 / $total" | bc)
    else
        cpu_idle=100
        io_wait=0
    fi
    
    # Calculate load as percentage of CPU cores, handle empty load1
    if [ -n "$load1" ] && [ "$CPU_CORES" -gt 0 ]; then
        load_percent=$(echo "scale=2; $load1 * 100 / $CPU_CORES" | bc)
    else
        load_percent=0
    fi

    echo "$load1 $load5 $load15 $cpu_idle $io_wait $load_percent"
}

get_memory_pressure() {
    if [ -r /proc/pressure/memory ]; then
        awk '/^some/ {for(i=1;i<=NF;i++) if($i ~ /avg10=/) {gsub("avg10=", "", $i); print $i; exit}}' /proc/pressure/memory
    else
        echo "0"
    fi
}

# -----------------------------
# Swap Usage by Process Detection
# -----------------------------
get_swap_usage_by_process() {
    echo "Processes Using Swap:"
    local found_swap=0
    declare -a swap_processes
    
    for pid in $(find /proc -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | cut -d'/' -f3); do
        if [ -f "/proc/$pid/smaps" ] && [ -r "/proc/$pid/smaps" ]; then
            local swap_kb
            swap_kb=$(grep Swap "/proc/$pid/smaps" 2>/dev/null | awk '{ sum+=$2; } END { print sum }')
            
            if [ -n "$swap_kb" ] && [ "$swap_kb" -gt 1024 ]; then  # Only show >1MB swap usage
                local proc_name
                proc_name=$(ps -p "$pid" -o comm= 2>/dev/null)
                if [ -n "$proc_name" ]; then
                    found_swap=1
                    local swap_mb
                    swap_mb=$(echo "scale=1; $swap_kb / 1024" | bc)
                    swap_processes+=("$swap_mb:$proc_name (PID $pid)")
                fi
            fi
        fi
    done
    
    if [ "$found_swap" -eq 1 ]; then
        printf '%s\n' "${swap_processes[@]}" | sort -hr -t: -k1 | head -8 | while IFS=: read -r swap_mb process; do
            echo "  $process: ${swap_mb} MB"
        done
    else
        echo "  No significant swap usage detected"
    fi
}

# -----------------------------
# System Collapse Detection - Only "On Its Knees" Scenarios
# -----------------------------
evaluate_system_collapse() {
    local mem_percent_free=$1 swap_percent_used=$2 mem_avail_kb=$3 
    local load_percent=$4 cpu_idle=$5 io_wait=$6 pressure=$7
    
    local collapse_detected=0
    local collapse_type=0
    local reasons=()
    
    local mem_avail_mb=$((mem_avail_kb / 1024))
    
    # =========================================================================
    # 1. INDIVIDUAL COLLAPSE SCENARIOS (System completely failing)
    # =========================================================================
    
    # Memory Collapse - System freezing due to OOM
    if [ "$(echo "$mem_percent_free < $MEMFREE_COLLAPSE_PERCENT" | bc -l)" -eq 1 ] || \
       [ "$mem_avail_mb" -lt "$MEMFREE_COLLAPSE_ABSOLUTE_MB" ]; then
        collapse_detected=1
        reasons=("MEMORY COLLAPSE: ${mem_percent_free}% free (${mem_avail_mb} MB) - SYSTEM FREEZING")
        echo "1 $MEMORY_SWAP_COLLAPSE ${reasons[*]}"
        return
    fi
    
    # Swap Collapse - Heavy thrashing making system unusable
    if [ "$(echo "$swap_percent_used > $SWAP_COLLAPSE_PERCENT" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        reasons=("SWAP COLLAPSE: ${swap_percent_used}% used - HEAVY THRASHING")
        echo "1 $MEMORY_SWAP_COLLAPSE ${reasons[*]}"
        return
    fi
    
    # CPU Collapse - System completely unresponsive
    if [ "$(echo "$load_percent > $LOAD_COLLAPSE_PERCENT" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        reasons=("CPU COLLAPSE: Load ${load_percent}% - SYSTEM UNRESPONSIVE")
        echo "1 $CPU_IO_COLLAPSE ${reasons[*]}"
        return
    fi
    
    # I/O Collapse - Disk completely bottlenecked
    if [ "$(echo "$io_wait > $IO_WAIT_COLLAPSE" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        reasons=("I/O COLLAPSE: ${io_wait}% wait - DISK BOTTLENECK")
        echo "1 $CPU_IO_COLLAPSE ${reasons[*]}"
        return
    fi
    
    # Memory Pressure Collapse - Kernel struggling severely
    if [ "$(echo "$pressure > $MEM_PRESSURE_COLLAPSE" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        reasons=("MEMORY PRESSURE COLLAPSE: ${pressure}% - KERNEL STRUGGLING")
        echo "1 $MEMORY_PRESSURE_SWAP_COLLAPSE ${reasons[*]}"
        return
    fi
    
    # =========================================================================
    # 2. COMBINATION COLLAPSE SCENARIOS (Multiple failure conditions)
    # =========================================================================
    
    # Combination 1: Memory Exhaustion + Heavy Swap (Classic system collapse)
    if [ "$(echo "$mem_percent_free < 5" | bc -l)" -eq 1 ] && \
       [ "$(echo "$swap_percent_used > 80" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        collapse_type=$MEMORY_SWAP_COLLAPSE
        reasons=("MEMORY+SWAP COLLAPSE: ${mem_percent_free}% free, ${swap_percent_used}% swap - SYSTEM THRASHING")
    fi
    
    # Combination 2: CPU Saturation + I/O Blockage (Complete resource deadlock)
    if [ "$(echo "$load_percent > 150" | bc -l)" -eq 1 ] && \
       [ "$(echo "$io_wait > 15" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        collapse_type=$CPU_IO_COLLAPSE
        reasons=("CPU+I/O COLLAPSE: Load ${load_percent}%, I/O ${io_wait}% - RESOURCE DEADLOCK")
    fi
    
    # Combination 3: Severe Memory Pressure + High Swap (Kernel memory crisis)
    if [ "$(echo "$pressure > 25" | bc -l)" -eq 1 ] && \
       [ "$(echo "$swap_percent_used > 70" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        collapse_type=$MEMORY_PRESSURE_SWAP_COLLAPSE
        reasons=("MEMORY PRESSURE+SWAP COLLAPSE: Pressure ${pressure}%, Swap ${swap_percent_used}% - KERNEL CRISIS")
    fi
    
    # Combination 4: Complete System Collapse (3+ collapse conditions)
    local collapse_count=0
    [ "$(echo "$mem_percent_free < 3" | bc -l)" -eq 1 ] && collapse_count=$((collapse_count + 1))
    [ "$(echo "$swap_percent_used > 85" | bc -l)" -eq 1 ] && collapse_count=$((collapse_count + 1))
    [ "$(echo "$load_percent > 180" | bc -l)" -eq 1 ] && collapse_count=$((collapse_count + 1))
    [ "$(echo "$io_wait > 20" | bc -l)" -eq 1 ] && collapse_count=$((collapse_count + 1))
    [ "$(echo "$pressure > 30" | bc -l)" -eq 1 ] && collapse_count=$((collapse_count + 1))
    
    if [ "$collapse_count" -ge 3 ]; then
        collapse_detected=1
        collapse_type=$COMPLETE_COLLAPSE
        reasons=("COMPLETE SYSTEM COLLAPSE: ${collapse_count} resources failed - IMMEDIATE ACTION REQUIRED")
    fi
    
    # =========================================================================
    # 3. EXTREME SINGLE-PARAMETER COLLAPSE (Absolute worst-case)
    # =========================================================================
    
    # Memory completely exhausted
    if [ "$(echo "$mem_percent_free < 0.5" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        reasons=("CRITICAL MEMORY COLLAPSE: <0.5% free - OOM KILLER ACTIVE")
        echo "1 $MEMORY_SWAP_COLLAPSE ${reasons[*]}"
        return
    fi
    
    # CPU completely saturated
    if [ "$(echo "$load_percent > 400" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        reasons=("CRITICAL CPU COLLAPSE: Load >400% - SYSTEM FROZEN")
        echo "1 $CPU_IO_COLLAPSE ${reasons[*]}"
        return
    fi
    
    # I/O completely blocked
    if [ "$(echo "$io_wait > 40" | bc -l)" -eq 1 ]; then
        collapse_detected=1
        reasons=("CRITICAL I/O COLLAPSE: ${io_wait}% wait - DISK DEADLOCK")
        echo "1 $CPU_IO_COLLAPSE ${reasons[*]}"
        return
    fi
    
    if [ "$collapse_detected" -eq 1 ]; then
        echo "1 $collapse_type ${reasons[*]}"
    else
        echo "0 0 OPERATIONAL"
    fi
}

# -----------------------------
# OOM Detection - Ultimate Collapse Indicator
# -----------------------------
check_recent_oom() {
    local current_time recent_oom since_arg
    current_time=$(date +%s)
    since_arg="@$LAST_OOM_CHECK"

    if command -v journalctl >/dev/null 2>&1; then
        recent_oom=$(journalctl -k --since "$since_arg" 2>/dev/null | grep -E "Out of memory|Killed process" | tail -3)
    else
        recent_oom=$(dmesg -T --since "$since_arg" 2>/dev/null | grep -E "Out of memory|Killed process" | tail -3)
        if [ $? -ne 0 ] || [ -z "$recent_oom" ]; then
            recent_oom=$(dmesg -T 2>/dev/null | grep -E "Out of memory|Killed process" | tail -3)
        fi
    fi

    LAST_OOM_CHECK=$current_time

    if [ -n "$recent_oom" ]; then
        log "OOM COLLAPSE DETECTED:"
        while IFS= read -r line; do
            log "  $line"
        done <<< "$recent_oom"
        return 1
    fi
    return 0
}

# -----------------------------
# Process Analysis for Collapse Scenarios
# -----------------------------
get_top_memory_processes() {
    ps -eo pid,ppid,user,%mem,rss,comm --sort=-%mem --no-headers 2>/dev/null | head -6 | \
    awk '{rss_mb=$5/1024; printf "  %-20s (PID %6s): %5.1f%% - %6.1f MB\n", $6, $1, $4, rss_mb}'
}

get_top_cpu_processes() {
    ps -eo pid,ppid,user,%cpu,comm --sort=-%cpu --no-headers 2>/dev/null | head -6 | \
    awk '{printf "  %-20s (PID %6s): %5.1f%%\n", $5, $1, $4}'
}

# -----------------------------
# System Information
# -----------------------------
get_system_info() {
    echo "Host: $(hostname) | Cores: $CPU_CORES"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime | cut -d',' -f1)"
    echo "Load: $(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3)"
}

# -----------------------------
# Collapse Alert Management
# -----------------------------
send_collapse_alert() {
    local message="$1"
    log "SYSTEM COLLAPSE ALERT: $message"
    
    if command -v notify-send >/dev/null 2>&1; then
        local short_message=$(echo "$message" | head -6)
        notify-send -u critical -t 15000 "💥 SYSTEM COLLAPSE DETECTED" "$short_message"
    fi
    
    # Also print to terminal for immediate visibility
    echo "💥 💥 💥 SYSTEM COLLAPSE DETECTED 💥 💥 💥"
    echo "$message"
}

should_send_alert() {
    local now
    now=$(date +%s)
    [ $((now - LAST_ALERT_TIME)) -ge "$ALERT_COOLDOWN" ]
}

# -----------------------------
# Main Monitoring Loop
# -----------------------------
main() {
    if ! command -v bc >/dev/null 2>&1; then
        echo "Error: 'bc' command required but not installed." >&2
        exit 1
    fi

    init_log
    log "Starting System Collapse Monitor - Only 'On Its Knees' Detection"
    log "CPU Cores: $CPU_CORES | Monitoring: System collapse scenarios only"
    echo "Monitoring for SYSTEM COLLAPSE every ${CHECK_INTERVAL}s"
    echo "Only alerts when system is 'on its knees' or about to fail completely"
    echo "Collapse thresholds:"
    echo "  Memory: <2% free OR <128MB | Swap: >90% used"
    echo "  CPU: Load >200% | I/O Wait: >25% | Pressure: >35%"
    echo "  Combinations: Memory+Swap, CPU+I/O, Complete collapse"

    while true; do
        rotate_logs

        # Collect all metrics
        read -r mem_percent_free swap_percent_used mem_avail_kb swap_total_kb < <(get_memory_metrics)
        read -r load1 load5 load15 cpu_idle io_wait load_percent < <(get_cpu_metrics)
        local pressure=$(get_memory_pressure)

        # Set default values if any CPU variables are empty (safety check)
        load1=${load1:-0}
        cpu_idle=${cpu_idle:-100}
        io_wait=${io_wait:-0}
        load_percent=${load_percent:-0}

        # Evaluate system collapse (only true failure scenarios)
        read -r collapse_detected collapse_type reasons < <(evaluate_system_collapse \
            "$mem_percent_free" "$swap_percent_used" "$mem_avail_kb" \
            "$load_percent" "$cpu_idle" "$io_wait" "$pressure")

        # Check for OOM events (ultimate collapse indicator)
        local oom_detected=0
        if ! check_recent_oom; then
            oom_detected=1
            collapse_detected=1
            collapse_type=$MEMORY_SWAP_COLLAPSE
            reasons="OOM KILLER ACTIVE: System killing processes to survive"
        fi

        # Trigger alert ONLY for system collapse
        if [ "$collapse_detected" -eq 1 ] || [ "$oom_detected" -eq 1 ]; then
            local current_time
            current_time=$(date +%s)

            if should_send_alert || [ "$oom_detected" -eq 1 ]; then
                local message system_info
                system_info=$(get_system_info)
                
                message="$system_info\n\n"
                message+="💥 SYSTEM COLLAPSE DETECTED 💥\n\n"
                message+="IMMEDIATE ACTION REQUIRED!\n\n"
                
                message+="COLLAPSE SCENARIO:\n"
                message+="• $reasons\n"
                
                message+="\nCURRENT SYSTEM STATE:\n"
                message+="• Memory: ${mem_percent_free}% free ($((mem_avail_kb / 1024)) MB available)\n"
                message+="• Swap: ${swap_percent_used}% used\n"
                message+="• CPU Load: ${load1} (${load_percent}% of capacity)\n"
                message+="• CPU Idle: ${cpu_idle}% | I/O Wait: ${io_wait}%\n"
                message+="• Memory Pressure: ${pressure}%\n"
                
                # Show relevant process analysis
                if [[ "$reasons" == *"MEMORY"* ]] || [[ "$reasons" == *"SWAP"* ]] || [ "$oom_detected" -eq 1 ]; then
                    message+="\nMEMORY COLLAPSE ANALYSIS:\n"
                    message+="$(get_swap_usage_by_process)\n"
                    message+="\nTOP MEMORY PROCESSES:\n$(get_top_memory_processes)\n"
                fi
                
                if [[ "$reasons" == *"CPU"* ]] || [[ "$reasons" == *"I/O"* ]] || [[ "$reasons" == *"LOAD"* ]]; then
                    message+="\nTOP CPU PROCESSES:\n$(get_top_cpu_processes)\n"
                fi
                
                message+="\nRECOMMENDED ACTIONS:\n"
                message+="• Kill largest memory processes if OOM detected\n"
                message+="• Consider emergency reboot if system unresponsive\n"
                message+="• Check disk health if I/O wait extreme\n"

                send_collapse_alert "$message"
                log "SYSTEM COLLAPSE: $reasons"
                LAST_ALERT_TIME=$current_time
            else
                log "Collapse alert suppressed (cooldown): $reasons"
            fi
        else
            # Only log normal operation occasionally to reduce log noise
            local current_minute
            current_minute=$(date +%M)
            if [ "$current_minute" -eq "0" ] || [ "$current_minute" -eq "30" ]; then
                log "System operational - Memory:${mem_percent_free}% free, Swap:${swap_percent_used}% used, Load:${load_percent}%"
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Cleanup handler
cleanup() {
    log "System collapse monitoring stopped"
    exit 0
}

trap cleanup EXIT INT TERM

main "$@"
