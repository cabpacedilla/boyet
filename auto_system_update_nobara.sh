#!/usr/bin/env bash
set -uo pipefail   # NO -e - we handle errors gracefully

# ================= CONFIG =================
STATE_DIR="$HOME/.auto_update_state"
LOG_DIR="$HOME/scriptlogs"
LOGFILE="$LOG_DIR/nobara_update_log.txt"
HISTORY_LOG="$LOG_DIR/update_history.csv"
VERIFICATION_LOG_DIR="$STATE_DIR/verifications"
LOCK_FILE="/tmp/auto_system_update_nobara_$(whoami).lock"

DRY_RUN=false
TIMEOUT_SECONDS=3600
MIN_DISK_SPACE_GB=5
MIN_DISK_SPACE_WARN_GB=10
MIN_BATTERY_PCT=30
MAX_LOG_AGE_DAYS=30
MAX_VERIFICATION_AGE_DAYS=90
MAX_NOTIFICATION_ITEMS=30

# Critical services to monitor (triggers warning if any fail)
readonly CRITICAL_SERVICES="NetworkManager.service|sshd.service|dbus.service|systemd-logind.service"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$VERIFICATION_LOG_DIR" || {
    echo "FATAL: Cannot create required directories" >&2
    exit 1
}

rm -f "$STATE_DIR/last_result" 2>/dev/null || true

# ================= LOG =================
log() {
    echo "$(date '+%F %T') - $*" | tee -a "$LOGFILE"
}

log_raw() {
    echo "$*" | tee -a "$LOGFILE"
}

log_blank() {
    echo "" >> "$LOGFILE"
    echo ""
}

# ================= NOTIFY =================
notify() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    notify-send -u "${2:-normal}" -t "${3:-5000}" "Auto Update" "$1"
}

notify_with_list() {
    local title="$1"
    local body="$2"
    local urgency="${3:-normal}"
    local timeout="${4:-0}"
    
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    
    local formatted_body="${body//\\n/$'\n'}"
    if [[ ${#formatted_body} -gt 3000 ]]; then
        formatted_body="${formatted_body:0:3000}..."
    fi
    
    notify-send -u "$urgency" -t "$timeout" "Auto Update: $title" "$formatted_body" 2>/dev/null || {
        DISPLAY=:0 notify-send -u "$urgency" -t "$timeout" "Auto Update: $title" "$formatted_body" 2>/dev/null || true
    }
}

alert_failure() {
    log "ALERT: $1"
    notify "$1" critical
}

# ================= INTERNET CONNECTION DETECTION =================
check_internet() {
    local endpoints=(
        "https://www.google.com"
        "https://www.cloudflare.com"
        "https://www.microsoft.com"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -s --connect-timeout 5 --max-time 10 "$endpoint" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# ================= GLOBAL CLEANUP =================
KEEP_ALIVE_PID=""

cleanup_keepalive() {
    if [[ -n "$KEEP_ALIVE_PID" ]]; then
        kill "$KEEP_ALIVE_PID" 2>/dev/null || true
        KEEP_ALIVE_PID=""
    fi
}

cleanup_lock() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

# ================= LOCK =================
exec 9>"$LOCK_FILE"
flock -n 9 || { 
    echo "$(date '+%F %T') - Already running" | tee -a "$LOGFILE"
    exit 1
}
trap 'cleanup_lock; cleanup_keepalive' EXIT INT TERM

# ================= SAFETY CHECKS =================
check_dnf_lock() {
    if pgrep -x dnf >/dev/null || pgrep -x rpm >/dev/null; then
        log "DNF/RPM already running, skipping..."
        return 1
    fi
    return 0
}

check_disk() {
    local avail
    avail=$(df -BG / | awk 'NR==2 {print $4}' | tr -d G)
    
    if [[ ! "$avail" =~ ^[0-9]+$ ]]; then
        log "Could not determine disk space (got: '$avail')"
        return 1
    fi
    
    if [[ "$avail" -lt "$MIN_DISK_SPACE_GB" ]]; then
        log "Low disk space: ${avail}GB available (min ${MIN_DISK_SPACE_GB}GB)"
        return 1
    fi
    return 0
}

BATTERY_WARNING_LOGGED=false

check_battery() {
    local battery_found=false
    for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/BATT*; do
        [[ -f "$bat/capacity" ]] || continue
        battery_found=true
        local cap status
        cap=$(<"$bat/capacity")
        status=$(<"$bat/status")
        
        if [[ ! "$cap" =~ ^[0-9]+$ ]]; then
            log "Unexpected battery capacity value: '$cap'"
            return 1
        fi
        
        if [[ "$status" != "Charging" && "$status" != "Full" && "$cap" -lt "$MIN_BATTERY_PCT" ]]; then
            log "Low battery: ${cap}% (min ${MIN_BATTERY_PCT}%), status: $status"
            return 1
        fi
    done
    
    if ! $battery_found && ! $BATTERY_WARNING_LOGGED; then
        log "No battery detected (desktop mode)"
        BATTERY_WARNING_LOGGED=true
    fi
    return 0
}

# ================= COOLDOWN FUNCTIONS =================
can_notify_idle() {
    local last_notify_file="$STATE_DIR/last_notify_idle"
    [[ ! -f "$last_notify_file" ]] && return 0
    local last_time=$(cat "$last_notify_file" 2>/dev/null || echo 0)
    [[ $(( $(date +%s) - last_time )) -gt 21600 ]]
}

can_notify_failure() {
    local last_failure_file="$STATE_DIR/last_failure_notify"
    [[ ! -f "$last_failure_file" ]] && return 0
    local last_time=$(cat "$last_failure_file" 2>/dev/null || echo 0)
    [[ $(( $(date +%s) - last_time )) -gt 3600 ]]
}

can_notify_warning() {
    local last_warning_file="$STATE_DIR/last_warning_notify"
    [[ ! -f "$last_warning_file" ]] && return 0
    local last_time=$(cat "$last_warning_file" 2>/dev/null || echo 0)
    [[ $(( $(date +%s) - last_time )) -gt 86400 ]]
}

can_notify_info() {
    local last_info_file="$STATE_DIR/last_info_notify"
    [[ ! -f "$last_info_file" ]] && return 0
    local last_time=$(cat "$last_info_file" 2>/dev/null || echo 0)
    [[ $(( $(date +%s) - last_time )) -gt 3600 ]]
}

update_notify_timestamp() { date +%s > "$STATE_DIR/last_notify_idle"; }
update_failure_timestamp() { date +%s > "$STATE_DIR/last_failure_notify"; }
update_warning_timestamp() { date +%s > "$STATE_DIR/last_warning_notify"; }
update_info_timestamp() { date +%s > "$STATE_DIR/last_info_notify"; }
update_success_timestamp() { date +%s > "$STATE_DIR/last_success"; }

# ================= POST-UPDATE VERIFICATION (LIGHTWEIGHT) =================
# Checks critical services, filesystem, and errors - NO heavy rpm -Va
verify_system_health() {
    local verification_log="$VERIFICATION_LOG_DIR/verification_$(date +%F-%H%M%S).log"
    local verification_failed=0
    local has_critical_failure=false
    local new_failures=""
    
    log "Running post-update system verification (quick check)..."
    
    # 1. Check for failed services (especially critical ones)
    local failed_services
    failed_services=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' || true)
    
    if [[ -n "$failed_services" ]]; then
        log "WARNING: Failed services detected:"
        echo "$failed_services" | while read -r service; do
            log "  - $service"
        done
        
        # Check if any critical service failed
        while IFS= read -r service; do
            if [[ -n "$service" ]] && echo "$service" | grep -qiE "$CRITICAL_SERVICES"; then
                log "CRITICAL: Critical service failure: $service"
                has_critical_failure=true
                new_failures+="  • $service (CRITICAL)\n"
            elif [[ -n "$service" ]]; then
                new_failures+="  • $service\n"
            fi
        done <<< "$failed_services"
        
        verification_failed=1
    else
        log "All services running normally."
    fi
    
    # 2. Check filesystem status (quick)
    if findmnt -n -o OPTIONS / 2>/dev/null | grep -E '(^|,)ro(,|$)' >/dev/null; then
        log "ERROR: Root filesystem is mounted read-only!"
        verification_failed=1
    else
        log "Root filesystem writable."
    fi
    
    # 3. Check for critical kernel errors since boot (limit to 10 lines)
    local critical_errors
    critical_errors=$(journalctl -b -p 2 --no-pager 2>/dev/null | head -10 || true)
    if [[ -n "$critical_errors" ]]; then
        log "WARNING: Critical kernel errors detected (first 10 lines shown)"
        echo "$critical_errors" | while read -r line; do
            log "  $line"
        done
        verification_failed=1
    else
        log "No critical kernel errors found."
    fi
    
    # Write verification report
    {
        echo "=========================================="
        echo "Nobara Post-Update Verification Report"
        echo "=========================================="
        echo "Time: $(date '+%F %T')"
        echo "Host: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo ""
        echo "1. FAILED SERVICES:"
        echo "------------------"
        if [[ -n "$failed_services" ]]; then
            echo "$failed_services"
        else
            echo "None"
        fi
        echo ""
        echo "2. CRITICAL SERVICE FAILURES:"
        echo "----------------------------"
        if [[ "$has_critical_failure" == "true" ]]; then
            echo "YES - Manual intervention recommended"
        else
            echo "None"
        fi
        echo ""
        echo "3. FILESYSTEM STATUS:"
        echo "--------------------"
        if findmnt -n -o OPTIONS / 2>/dev/null | grep -q "ro"; then
            echo "READ-ONLY - CRITICAL"
        else
            echo "Writable - OK"
        fi
        echo ""
        echo "4. KERNEL ERRORS (last 10):"
        echo "--------------------------"
        echo "$critical_errors"
        echo ""
        echo "=========================================="
        if [[ $verification_failed -eq 1 ]]; then
            echo "STATUS: ISSUES DETECTED"
        else
            echo "STATUS: HEALTHY"
        fi
        echo "=========================================="
    } > "$verification_log" 2>&1
    
    cat "$verification_log" >> "$LOGFILE"
    
    # Send notification if issues found
    if [[ $verification_failed -eq 1 ]]; then
        log "Post-update verification found issues - see $verification_log"
        
        if [[ "$has_critical_failure" == "true" ]]; then
            notify_with_list "⚠️ CRITICAL ISSUES DETECTED" "Critical services failed after update:\n\n$new_failures\n\nCheck log: $verification_log" "critical" 0
        else
            notify "Post-update issues detected - check verification log" normal
        fi
    else
        log "Post-update verification passed - system healthy"
    fi
    
    # Clean old verification logs
    find "$VERIFICATION_LOG_DIR" -type f -name "verification_*.log" -mtime +"$MAX_VERIFICATION_AGE_DAYS" -delete 2>/dev/null || true
    
    return $verification_failed
}

# ================= REBOOT TRACKING =================
REBOOT_NOTIFIED_FILE="$STATE_DIR/reboot_notified"
REBOOT_NOTIFIED=false

case "$(tr -d '[:space:]' < "$REBOOT_NOTIFIED_FILE" 2>/dev/null || echo false)" in
    true) REBOOT_NOTIFIED=true ;;
    *)    REBOOT_NOTIFIED=false ;;
esac

quick_verify() {
    local issues_found=0
    
    # Check for failed services
    if systemctl --failed --no-legend 2>/dev/null | grep -q "."; then
        log "Quick check: Failed services detected"
        notify "System degraded - check 'systemctl --failed'" critical
        issues_found=1
    fi
    
    # Check if reboot needed for kernel
    local installed_kernel
    local running_kernel
    installed_kernel=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-//')
    running_kernel=$(uname -r)
    
    if [[ "$installed_kernel" != "$running_kernel" ]]; then
        if [[ "$REBOOT_NOTIFIED" != "true" ]]; then
            log "Quick check: Reboot recommended - kernel updated to $installed_kernel (current: $running_kernel)"
            notify "🔁 RESTART REQUIRED!\n\nKernel updated from $running_kernel to $installed_kernel\nPlease reboot your system." critical 0
            REBOOT_NOTIFIED=true
            printf 'true' > "$REBOOT_NOTIFIED_FILE"
        fi
    else
        if [[ "$REBOOT_NOTIFIED" != "false" ]]; then
            REBOOT_NOTIFIED=false
            printf 'false' > "$REBOOT_NOTIFIED_FILE"
        fi
    fi
    
    return $issues_found
}

# ================= FETCH UPDATES =================
fetch_pending_updates() {
    local tmp
    tmp=$(mktemp) || { log "Failed to create temp file"; return 1; }
    
    trap 'rm -f "$tmp"' RETURN

    # Metadata refresh
    sudo dnf makecache -q >> "$LOGFILE" 2>&1 || true
    sudo dnf check-update > "$tmp" 2>/dev/null || true
    
    # Extract DNF updates
    if grep -q -E '\.(x86_64|noarch|i686|aarch64)' "$tmp" 2>/dev/null; then
        grep -E '\.(x86_64|noarch|i686|aarch64)' "$tmp" \
            | awk '{print $1 " (" $2 ")"}' > "$STATE_DIR/dnf_list"
    else
        > "$STATE_DIR/dnf_list"
    fi

    # Extract Flatpak updates
    if command -v flatpak >/dev/null; then
        flatpak remote-ls --updates 2>/dev/null | tail -n +2 \
            | awk '{if(NF>=2) print $1 " (" $2 ")"; else print $1}' \
            > "$STATE_DIR/flatpak_list" 2>/dev/null || true
    else
        > "$STATE_DIR/flatpak_list"
    fi
}

updates_available() {
    [[ -s "$STATE_DIR/dnf_list" || -s "$STATE_DIR/flatpak_list" ]]
}

# ================= BUILD NOTIFICATION LISTS =================
build_update_list() {
    local dnf_list=""
    local flatpak_list=""
    local dnf_count=0
    local flatpak_count=0
    
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        dnf_count=$(wc -l < "$STATE_DIR/dnf_list")
        dnf_list="📦 <b>Packages ($dnf_count):</b>\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $MAX_NOTIFICATION_ITEMS ]]; do
            dnf_list+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/dnf_list"
        if [[ $dnf_count -gt $MAX_NOTIFICATION_ITEMS ]]; then
            dnf_list+="  ... and $((dnf_count - MAX_NOTIFICATION_ITEMS)) more\n"
        fi
    fi
    
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
        flatpak_list="🟢 <b>Flatpaks ($flatpak_count):</b>\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $MAX_NOTIFICATION_ITEMS ]]; do
            flatpak_list+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/flatpak_list"
        if [[ $flatpak_count -gt $MAX_NOTIFICATION_ITEMS ]]; then
            flatpak_list+="  ... and $((flatpak_count - MAX_NOTIFICATION_ITEMS)) more\n"
        fi
    fi
    
    local combined_list=""
    if [[ -n "$dnf_list" ]]; then
        combined_list="$dnf_list"
    fi
    if [[ -n "$flatpak_list" ]]; then
        [[ -n "$combined_list" ]] && combined_list+="\n"
        combined_list+="$flatpak_list"
    fi
    
    echo "$combined_list"
    return $((dnf_count + flatpak_count))
}

# ================= NOTIFICATIONS =================
notify_pending() {
    local update_list
    local total_count
    
    update_list=$(build_update_list)
    total_count=$?
    
    if [[ -n "$update_list" ]]; then
        notify_with_list "📦 Updates Detected" "Installing $total_count updates...\n\n$update_list" "normal" 0
    else
        notify "Found updates: $total_count items" normal
    fi
    
    # Log to file as well
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        log_raw "Pending packages:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/dnf_list"
    fi
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        log_raw "Pending flatpaks:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/flatpak_list"
    fi
}

notify_complete_with_list() {
    local update_list
    local total_count
    
    update_list=$(build_update_list)
    total_count=$?
    
    if [[ -n "$update_list" ]]; then
        notify_with_list "✅ Updates Complete" "Successfully updated $total_count items!\n\n$update_list" "normal" 10000
    else
        notify "Updates completed successfully" normal
    fi
}

notify_complete() {
    notify_complete_with_list
}

# ================= RUN UPDATES =================
LAST_DNF_EXIT=""
LAST_FLATPAK_EXIT=""

run_updates() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY_RUN] Skipping actual updates."
        LAST_DNF_EXIT="dry-run"
        LAST_FLATPAK_EXIT="dry-run"
        return 0
    fi

    check_dnf_lock || { 
        LAST_DNF_EXIT="locked"
        LAST_FLATPAK_EXIT="skipped"
        return 1 
    }

    local DNF_EXIT=1 FLATPAK_EXIT=1
    local UPDATE_SUCCESS=1
    local TEMP_SYNC_LOG
    TEMP_SYNC_LOG=$(mktemp)

    # Start keep-alive loop (redirect output to /dev/null to reduce noise)
    while true; do 
        sudo -n true 2>/dev/null
        sleep 60
    done &> /dev/null &
    KEEP_ALIVE_PID=$!

    # Run Nobara sync - capture output to both log and temp file for success detection
    log_raw "=============================="
    log_raw "Starting Nobara System Update"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo nobara-sync cli 2>&1 | tee -a "$LOGFILE" | tee "$TEMP_SYNC_LOG"
    DNF_EXIT=${PIPESTATUS[0]}
    log_raw "Nobara-sync exit code: $DNF_EXIT"
    
    # Flatpak updates
    log_blank
    log_raw "=============================="
    log_raw "Starting Flatpak Updates"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo flatpak update -y 2>&1 | tee -a "$LOGFILE"
    FLATPAK_EXIT=${PIPESTATUS[0]}
    log_raw "Flatpak (system) exit code: $FLATPAK_EXIT"
    
    if [[ $FLATPAK_EXIT -eq 0 ]]; then
        timeout "$TIMEOUT_SECONDS" flatpak update --user -y 2>&1 | tee -a "$LOGFILE"
        FLATPAK_EXIT=${PIPESTATUS[0]}
        log_raw "Flatpak (user) exit code: $FLATPAK_EXIT"
    fi

    LAST_DNF_EXIT="$DNF_EXIT"
    LAST_FLATPAK_EXIT="$FLATPAK_EXIT"

    log_blank
    log_raw "=============================="
    log_raw "Update Summary"
    log_raw "=============================="
    
    # LENIENT SUCCESS CHECK - matches your original working script
    # Success if: (both exit codes are 0) OR (log contains "Complete!" or "All Updates complete")
    if [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -eq 0 ]] || \
       grep -qiE "Complete!|All Updates complete|Successfully" "$TEMP_SYNC_LOG" 2>/dev/null; then
        
        UPDATE_SUCCESS=0
        log_raw "Updates completed successfully"
        
        # SEND NOTIFICATION IMMEDIATELY (before verification)
        notify_complete
        
        # Run post-update cleanup
        log "Running post-update cleanup..."
        sudo dnf autoremove -y 2>&1 | tee -a "$LOGFILE"
        sudo dnf clean packages 2>&1 | tee -a "$LOGFILE"
        sudo flatpak uninstall --unused -y 2>&1 | tee -a "$LOGFILE"
        flatpak uninstall --user --unused -y 2>&1 | tee -a "$LOGFILE"
        
        log_blank
        log_raw "=============================="
        log_raw "Post-Update Verification"
        log_raw "=============================="
        
        # Run verification (lightweight - no rpm -Va)
        verify_system_health || true
    else
        log_raw "Updates failed (Nobara: $DNF_EXIT, Flatpak: $FLATPAK_EXIT)"
        alert_failure "Update failed - check log for details"
    fi

    # Clean up temp file
    rm -f "$TEMP_SYNC_LOG" 2>/dev/null || true
    
    cleanup_keepalive
    return "$UPDATE_SUCCESS"
}

# ================= ROTATE LOGS =================
rotate_logs() {
    find "$LOG_DIR" -type f \( -name "*.txt" -o -name "*.csv" \) -mtime +"$MAX_LOG_AGE_DAYS" -delete 2>/dev/null
}

# ================= MAIN LOOP WITH EXPONENTIAL SLEEP =================
main() {
    for arg in "$@"; do
        if [[ "$arg" == "--dry-run" ]]; then
            DRY_RUN=true
            break
        fi
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Auto-update service starting (PID $$) - DRY RUN MODE"
    else
        log "Auto-update service starting (PID $$)"
    fi

    local retry_delay=60
    local max_delay=3600

    while true; do
        # ================= INTERNET CONNECTION CHECK WITH EXPONENTIAL SLEEP =================
        if ! check_internet; then
            local offline_start=$(date +%s)
            local sleep_time=60      # Start with 1 minute
            local max_sleep=3600     # Max 1 hour
            local notified_prolonged=false
            
            log "🌐 No internet connection detected"
            if can_notify_warning; then
                notify "🌐 No internet connection - updates postponed" "normal" 5000
                update_warning_timestamp
            fi
            
            # Exponential backoff until internet returns
            while ! check_internet; do
                local offline_min=$(( ($(date +%s) - offline_start) / 60 ))
                log "Still offline after ${offline_min} minutes, sleeping ${sleep_time}s before next check"
                
                # Notify once after 30 minutes of being offline
                if (( offline_min >= 30 )) && [[ "$notified_prolonged" == "false" ]]; then
                    if can_notify_warning; then
                        notify "Still offline after 30 minutes - updates will resume when connection returns" "normal" 5000
                        update_warning_timestamp
                        notified_prolonged=true
                    fi
                fi
                
                sleep "$sleep_time"
                
                # Exponential backoff with cap
                sleep_time=$(( sleep_time * 2 ))
                if (( sleep_time > max_sleep )); then
                    sleep_time=$max_sleep
                fi
            done
            
            local offline_duration=$(( ($(date +%s) - offline_start) / 60 ))
            log "🌐 Internet connection restored after ${offline_duration} minutes"
            notify "🌐 Internet connection restored - resuming update checks" "normal" 5000
        fi
        
        # Disk check
        if ! check_disk; then 
            log "Disk check failed, retrying in ${retry_delay}s"
            sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi
        
        # Battery check
        if ! check_battery; then 
            log "Battery check failed, retrying in ${retry_delay}s"
            sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi

        # Reset retry delay after successful checks
        retry_delay=60

        fetch_pending_updates

        if updates_available; then
            notify_pending
            if run_updates; then
                echo "$(date '+%F'),OK,DNF:${LAST_DNF_EXIT},FLATPAK:${LAST_FLATPAK_EXIT}" >> "$HISTORY_LOG"
                log "Update cycle completed successfully"
                update_success_timestamp
            else
                echo "$(date '+%F'),FAIL,DNF:${LAST_DNF_EXIT:-unknown},FLATPAK:${LAST_FLATPAK_EXIT:-unknown}" >> "$HISTORY_LOG"
                log "Update cycle failed"
            fi
        else
            log "System is up to date."
            notify "System is up to date." critical 0
            quick_verify
        fi

        rotate_logs
        sleep 1h
    done
}

main "$@"
