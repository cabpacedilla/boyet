#!/usr/bin/env bash
# ============================================================================
# Nobara Linux Auto-Update Daemon
# ============================================================================

set -uo pipefail

# ================= CONFIG =================
STATE_DIR="$HOME/.auto_update_state"
LOG_DIR="$HOME/scriptlogs"
LOGFILE="$LOG_DIR/nobara_update_log.txt"
HISTORY_LOG="$LOG_DIR/update_history.csv"
VERIFICATION_LOG_DIR="$STATE_DIR/verifications"
LOCK_FILE="$STATE_DIR/auto_update.lock"

DRY_RUN=false
ENABLE_AUTOREMOVE=false
TIMEOUT_SECONDS=3600
MIN_DISK_SPACE_GB=5
MIN_BATTERY_PCT=30
MAX_LOG_AGE_DAYS=30
MAX_VERIFICATION_AGE_DAYS=90
MAX_NOTIFICATION_ITEMS=30

readonly CRITICAL_SERVICES="NetworkManager.service|sshd.service|dbus.service|systemd-logind.service"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$VERIFICATION_LOG_DIR" "$LOG_DIR/archive" || {
    echo "FATAL: Cannot create directories" >&2
    exit 1
}

# Initialize CSV header for update_history.csv
if [[ ! -s "$HISTORY_LOG" ]]; then
    printf '%s\n' "DATE,STATUS,DNF_COUNT,FLATPAK_COUNT" > "$HISTORY_LOG"
fi

# Persist timestamps
SYSTEM_UPTODATE_LOG_FILE="$STATE_DIR/last_system_uptodate_log"
SYSTEM_UPTODATE_NOTIFY_FILE="$STATE_DIR/last_system_uptodate_notify"

# Pre-update state tracking
PRE_UPDATE_KERNEL_FILE="$STATE_DIR/pre_update_kernel"
PRE_UPDATE_TRANSACTION_FILE="$STATE_DIR/pre_update_transaction"
POST_UPDATE_KERNEL_FILE="$STATE_DIR/post_update_kernel"

# ================= MANUAL ROLLBACK INSTRUCTIONS =================
# If the system fails to boot after an update, you can manually roll back:
#
# 1. Roll back DNF transaction:
#    dnf history list
#    sudo dnf history rollback <TRANSACTION_ID>
#
# 2. Roll back to previous kernel (at GRUB boot menu):
#    Select "Advanced Options" → Previous kernel
#    Or make permanent: sudo grubby --set-default /boot/vmlinuz-<previous-version>
#
# 3. Check saved pre-update state:
#    cat ~/.auto_update_state/pre_update_kernel
#    cat ~/.auto_update_state/pre_update_transaction
#
# The script stores this information to assist with manual recovery.

# ================= ATOMIC FILE WRITES =================
safe_write_timestamp() {
    local target="$1"
    local tmp
    tmp=$(mktemp "$STATE_DIR/tmp.ts.XXXXXX") 2>/dev/null || return 1
    date +%s > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || return 1
}

safe_write_content() {
    local target="$1"
    local content="$2"
    local tmp
    tmp=$(mktemp "$STATE_DIR/tmp.content.XXXXXX") 2>/dev/null || return 1
    printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || return 1
}

mktemp_safe() {
    mktemp "$STATE_DIR/tmp.XXXXXX" 2>/dev/null || {
        echo "FATAL: mktemp failed" >> "$LOGFILE"
        return 1
    }
}

# ================= LOGGING =================
log() {
    printf '%s %s\n' "$(date '+%F %T')" "- $*" | tee -a "$LOGFILE"
}

log_raw() {
    printf '%s\n' "$*" | tee -a "$LOGFILE"
}

log_blank() {
    printf '\n' >> "$LOGFILE"
}

# ================= NOTIFICATION =================
LAST_SYSTEM_UP_TO_DATE_NOTIFY=0

notify() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    
    local message="$1"
    local urgency="${2:-normal}"
    local timeout="${3:-5000}"
    
    if [[ -n "${DISPLAY:-}" ]]; then
        DISPLAY="$DISPLAY" notify-send -u "$urgency" -t "$timeout" "Auto Update" "$message" 2>/dev/null && return 0
    fi
    DISPLAY=":0" notify-send -u "$urgency" -t "$timeout" "Auto Update" "$message" 2>/dev/null && return 0
    return 0
}

notify_with_list() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    
    local title="$1"
    local body="$2"
    local urgency="${3:-normal}"
    local timeout="${4:-0}"
    
    local plain_body="${body//<b>/}"
    plain_body="${plain_body//<\/b>/}"
    [[ ${#plain_body} -gt 3000 ]] && plain_body="${plain_body:0:3000}..."
    
    if [[ -n "${DISPLAY:-}" ]]; then
        DISPLAY="$DISPLAY" notify-send -u "$urgency" -t "$timeout" "Auto Update: $title" "$plain_body" 2>/dev/null && return 0
    fi
    DISPLAY=":0" notify-send -u "$urgency" -t "$timeout" "Auto Update: $title" "$plain_body" 2>/dev/null && return 0
    return 0
}

alert_failure() {
    log "ALERT: $1"
    notify "$1" critical
}

system_up_to_date() {
    local now=$(date +%s)
    local last_log=0
    if [[ -f "$SYSTEM_UPTODATE_LOG_FILE" ]]; then
        last_log=$(<"$SYSTEM_UPTODATE_LOG_FILE")
        [[ ! "$last_log" =~ ^[0-9]+$ ]] && last_log=0
    fi
    
    if [[ $((now - last_log)) -ge 86400 ]]; then
        log "System is up to date."
        safe_write_timestamp "$SYSTEM_UPTODATE_LOG_FILE"
    fi
    notify "System is up to date." normal 3000
}

# ================= INTERNET =================
check_internet() {
    local endpoints=(
        "https://www.google.com"
        "https://www.cloudflare.com"
        "https://www.microsoft.com"
        "https://mirrors.fedoraproject.org"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -fsI --connect-timeout 5 --max-time 10 "$endpoint" >/dev/null 2>&1; then
            return 0
        fi
    done
    
    sudo dnf makecache --timer -q 2>/dev/null && return 0
    return 1
}

# ================= LOCK HANDLING =================
KEEP_ALIVE_PID=""
LOCK_ACQUIRED=false

cleanup_keepalive() {
    if [[ -n "${KEEP_ALIVE_PID:-}" ]] && kill -0 "$KEEP_ALIVE_PID" 2>/dev/null; then
        kill "$KEEP_ALIVE_PID" 2>/dev/null || true
        wait "$KEEP_ALIVE_PID" 2>/dev/null || true
    fi
    KEEP_ALIVE_PID=""
}

cleanup_lock() {
    if [[ "${LOCK_ACQUIRED:-false}" == "true" ]]; then
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        rm -f "$LOCK_FILE" 2>/dev/null || true
        LOCK_ACQUIRED=false
    fi
}

# exec 9>"$LOCK_FILE"
# if ! flock -n 9; then
#     printf '%s - Already running\n' "$(date '+%F %T')" | tee -a "$LOGFILE"
#     exit 1
# fi
# LOCK_ACQUIRED=true
# trap 'cleanup_keepalive; cleanup_lock' EXIT INT TERM

# ================= SAFETY CHECKS =================
check_package_lock() {
    pgrep -x dnf >/dev/null 2>&1 && { log "DNF already running, skipping..."; return 1; }
    pgrep -x rpm >/dev/null 2>&1 && { log "RPM already running, skipping..."; return 1; }
    pgrep -x packagekitd >/dev/null 2>&1 && { log "PackageKit running, skipping..."; return 1; }
    return 0
}

check_disk() {
    local avail
    avail=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
    
    if [[ -z "$avail" || ! "$avail" =~ ^[0-9]+$ ]]; then
        log "Could not determine disk space (got: '$avail')"
        return 1
    fi
    
    if [[ "$avail" -lt "$MIN_DISK_SPACE_GB" ]]; then
        log "Low disk space: ${avail}GB available"
        return 1
    fi
    return 0
}

BATTERY_WARNING_LOGGED=false

check_battery() {
    shopt -s nullglob
    local bat_files=(/sys/class/power_supply/BAT* /sys/class/power_supply/BATT*)
    shopt -u nullglob
    
    local found=false
    local cap status
    
    for bat in "${bat_files[@]}"; do
        [[ -f "$bat/capacity" ]] || continue
        found=true
        cap=$(<"$bat/capacity")
        status=$(<"$bat/status")
        
        [[ "$cap" =~ ^[0-9]+$ ]] || { log "Invalid battery capacity"; return 1; }
        
        if [[ "$status" != "Charging" && "$status" != "Full" && "$cap" -lt "$MIN_BATTERY_PCT" ]]; then
            log "Low battery: ${cap}% ($status)"
            return 1
        fi
    done
    
    if ! $found && command -v upower >/dev/null 2>&1; then
        local dev=$(upower -e 2>/dev/null | grep -i BAT | head -1)
        if [[ -n "$dev" ]]; then
            cap=$(upower -i "$dev" 2>/dev/null | awk '/percentage/ {gsub(/%/,"",$2); print $2}')
            status=$(upower -i "$dev" 2>/dev/null | awk '/state/ {print $2}')
            if [[ -n "$cap" && "$cap" =~ ^[0-9]+$ ]] && \
               [[ "$status" != "charging" && "$status" != "fully-charged" && "$cap" -lt "$MIN_BATTERY_PCT" ]]; then
                log "Low battery: ${cap}%"
                return 1
            fi
            found=true
        fi
    fi
    
    if ! $found && ! $BATTERY_WARNING_LOGGED; then
        log "No battery detected (desktop mode)"
        BATTERY_WARNING_LOGGED=true
    fi
    return 0
}

# ================= COOLDOWN FUNCTIONS =================
can_notify_warning() {
    local last_warning_file="$STATE_DIR/last_warning_notify"
    [[ ! -f "$last_warning_file" ]] && return 0
    local last_time=$(<"$last_warning_file")
    [[ ! "$last_time" =~ ^[0-9]+$ ]] && last_time=0
    [[ $(( $(date +%s) - last_time )) -gt 86400 ]]
}

can_notify_restored() {
    local last_restored_file="$STATE_DIR/last_restored_notify"
    [[ ! -f "$last_restored_file" ]] && return 0
    local last_time=$(<"$last_restored_file")
    [[ ! "$last_time" =~ ^[0-9]+$ ]] && last_time=0
    [[ $(( $(date +%s) - last_time )) -gt 3600 ]]
}

update_warning_timestamp() { safe_write_timestamp "$STATE_DIR/last_warning_notify"; }
update_restored_timestamp() { safe_write_timestamp "$STATE_DIR/last_restored_notify"; }
update_success_timestamp() { safe_write_timestamp "$STATE_DIR/last_success"; }

# ================= PRE-UPDATE STATE TRACKING =================
track_pre_update_state() {
    local current_kernel=$(uname -r)
    echo "$current_kernel" > "$PRE_UPDATE_KERNEL_FILE"
    log "📝 Pre-update kernel saved for reference: $current_kernel"
    
    local trans_id=$(dnf history list 2>/dev/null | grep -v "^ID" | head -1 | awk '{print $1}')
    if [[ -n "$trans_id" && "$trans_id" =~ ^[0-9]+$ ]]; then
        echo "$trans_id" > "$PRE_UPDATE_TRANSACTION_FILE"
        log "📝 Pre-update transaction ID saved: $trans_id"
        log "   Manual rollback: sudo dnf history rollback $trans_id"
    else
        log "⚠️ Could not determine current DNF transaction ID"
    fi
}

# ================= POST-UPDATE VERIFICATION =================
verify_system_health() {
    local verification_log="$VERIFICATION_LOG_DIR/verification_$(date +%F-%H%M%S).log"
    local verification_failed=0
    local has_critical_failure=false
    local new_failures=""
    local update_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "Running post-update system verification..."
    
    local failed_services
    failed_services=$(systemctl --failed --no-legend 2>/dev/null | grep -v "drkonqi-coredump-processor" | awk '{print $1}' || true)
    
    if [[ -n "$failed_services" ]]; then
        log "WARNING: Failed services detected:"
        while IFS= read -r service; do
            log "  - $service"
        done <<< "$failed_services"
        
        while IFS= read -r service; do
            if [[ -n "$service" ]] && echo "$service" | grep -qiE "$CRITICAL_SERVICES"; then
                log "CRITICAL: Critical service failure: $service"
                has_critical_failure=true
                new_failures+="  • $service (CRITICAL)\n"
                verification_failed=1
            fi
        done <<< "$failed_services"
    else
        log "All services running normally."
    fi
    
    if findmnt -n -o OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
        log "ERROR: Root filesystem is mounted read-only!"
        verification_failed=1
    else
        log "Root filesystem writable."
    fi
    
    local critical_errors
    critical_errors=$(journalctl --since "$update_start_time" -p 2 --no-pager 2>/dev/null | \
        grep -v -E "drkonqi|coredump|wireplumber.*crashed" | \
        head -10 || true)
    if [[ -n "$critical_errors" ]]; then
        log "WARNING: Critical kernel errors detected since update start"
        verification_failed=1
    else
        log "No critical kernel errors found."
    fi
    
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
        [[ -n "$failed_services" ]] && echo "$failed_services" || echo "None"
        echo ""
        echo "2. CRITICAL SERVICE FAILURES:"
        echo "----------------------------"
        [[ "$has_critical_failure" == "true" ]] && echo "YES - Manual intervention recommended" || echo "None"
        echo ""
        echo "3. FILESYSTEM STATUS:"
        echo "--------------------"
        if findmnt -n -o OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
            echo "READ-ONLY - CRITICAL"
        else
            echo "Writable - OK"
        fi
        echo ""
        echo "4. KERNEL ERRORS (since update start):"
        echo "--------------------------------------"
        echo "$critical_errors"
        echo ""
        echo "=========================================="
        [[ $verification_failed -eq 1 ]] && echo "STATUS: ISSUES DETECTED" || echo "STATUS: HEALTHY"
        echo "=========================================="
        
        if [[ $verification_failed -eq 1 ]]; then
            echo ""
            echo "MANUAL ROLLBACK INFO:"
            echo "--------------------"
            echo "To roll back this update:"
            echo "  sudo dnf history rollback $(cat "$PRE_UPDATE_TRANSACTION_FILE" 2>/dev/null || echo 'N/A')"
            echo "  Or select previous kernel at GRUB boot menu"
        fi
    } > "$verification_log" 2>&1
    
    cat "$verification_log" >> "$LOGFILE"
    
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
    
    find "$VERIFICATION_LOG_DIR" -type f -name "verification_*.log" -mtime +"$MAX_VERIFICATION_AGE_DAYS" -delete 2>/dev/null || true
    return $verification_failed
}

# ================= SECURITY CHECKS =================
post_update_security_check() {
    log "Running post-update security checks..."

    if command -v aa-status >/dev/null 2>&1; then
        aa-status >> "$LOGFILE" 2>&1 || log "AppArmor check failed"
    fi

    for svc in NetworkManager sshd dbus systemd-logind firewalld auditd; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log "✅ $svc is active"
        else
            log "⚠️ WARNING: $svc is not active"
        fi
    done

    log "Listening ports (ss -tulpn):"
    ss -tulpn 2>/dev/null | head -50 | while read -r line; do
        log_raw "  $line"
    done

    local auth_failures
    auth_failures=$(journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep -c "Failed password" || echo 0)
    if [[ $auth_failures -gt 0 ]]; then
        log "⚠️ $auth_failures authentication failures detected in last hour"
        journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep "Failed password" | tail -10 >> "$LOGFILE"
    else
        log "✅ No authentication failures in last hour"
    fi

    log "Recent kernel errors (last 50 lines):"
    journalctl -b -p 3 --no-pager 2>/dev/null | tail -50 | while read -r line; do
        log_raw "  $line"
    done

    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null | grep -v "drkonqi-coredump-processor" | awk '{print $1}' || true)
    if [[ -n "$failed_units" ]]; then
        log "⚠️ Failed systemd units detected:"
        while IFS= read -r unit; do
            log "  - $unit"
        done <<< "$failed_units"
    else
        log "✅ No failed systemd units"
    fi

    log "Post-update security checks completed."
}

# ================= REBOOT TRACKING =================
REBOOT_NOTIFIED_FILE="$STATE_DIR/reboot_notified"

is_reboot_needed() {
    local installed_kernel
    local running_kernel
    
    installed_kernel=$(rpm -q kernel-core --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-core-//')
    [[ -z "$installed_kernel" ]] && installed_kernel=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-//')
    running_kernel=$(uname -r)
    
    [[ -n "$installed_kernel" && "$installed_kernel" != "$running_kernel" ]]
}

clear_reboot_notification_if_not_needed() {
    if is_reboot_needed; then
        log "DEBUG: reboot IS needed (kernel versions differ)"
    else
        log "DEBUG: reboot NOT needed (kernel versions match)"
    fi
    
    if ! is_reboot_needed; then
        if [[ -f "$REBOOT_NOTIFIED_FILE" ]]; then
			local content
            content=$(<"$REBOOT_NOTIFIED_FILE")
            if [[ "$(tr -d '[:space:]' <<< "$content")" == "true" ]]; then
                safe_write_content "$REBOOT_NOTIFIED_FILE" "false"
                log "Cleared reboot notification (kernel versions now match)"
            fi
        fi
        REBOOT_NOTIFIED=false
        return 0
    fi
    return 1
}

REBOOT_NOTIFIED=false
if [[ -f "$REBOOT_NOTIFIED_FILE" ]]; then
    content=$(<"$REBOOT_NOTIFIED_FILE")
    if [[ "$(tr -d '[:space:]' <<< "$content")" == "true" ]]; then
        REBOOT_NOTIFIED=true
        log "DEBUG: Loaded REBOOT_NOTIFIED=true from file"
    else
        log "DEBUG: Loaded REBOOT_NOTIFIED=false from file"
    fi
fi

quick_verify() {
    local issues_found=0
    
    clear_reboot_notification_if_not_needed
    
    if systemctl --failed --no-legend 2>/dev/null | grep -v "drkonqi-coredump-processor" | grep -q "."; then
        log "Quick check: Failed services detected"
        notify "System degraded - check 'systemctl --failed'" critical
        issues_found=1
    fi
    
    local installed_kernel
    local running_kernel
    installed_kernel=$(rpm -q kernel-core --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-core-//')
    [[ -z "$installed_kernel" ]] && installed_kernel=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-//')
    running_kernel=$(uname -r)
    
    log "DEBUG: Kernel check - installed: $installed_kernel, running: $running_kernel"
    
    if [[ -n "$installed_kernel" && "$installed_kernel" != "$running_kernel" ]]; then
        if [[ "$REBOOT_NOTIFIED" != "true" ]]; then
            log "Quick check: Reboot recommended - kernel updated to $installed_kernel (current: $running_kernel)"
            log "   Manual rollback if needed: sudo grubby --set-default /boot/vmlinuz-$running_kernel"
            notify "🔁 RESTART REQUIRED!\n\nKernel updated from $running_kernel to $installed_kernel\nPlease reboot your system." critical 0
            REBOOT_NOTIFIED=true
            safe_write_content "$REBOOT_NOTIFIED_FILE" "true"
            log "DEBUG: Set REBOOT_NOTIFIED=true, wrote to file"
        else
            log "DEBUG: Reboot needed but already notified (REBOOT_NOTIFIED=$REBOOT_NOTIFIED)"
        fi
    else
        if [[ "$REBOOT_NOTIFIED" == "true" ]]; then
            safe_write_content "$REBOOT_NOTIFIED_FILE" "false"
            REBOOT_NOTIFIED=false
            log "Reboot notification cleared (kernel versions now match)"
        else
            log "DEBUG: No reboot needed and REBOOT_NOTIFIED=$REBOOT_NOTIFIED (no action)"
        fi
    fi
    
    return $issues_found
}

# ================= FETCH UPDATES =================
fetch_pending_updates() {
    local tmp
    tmp=$(mktemp_safe) || return 1
    
    {
        sudo dnf makecache --timer -q >> "$LOGFILE" 2>&1 || true
        
        local dnf_rc=0
        sudo dnf check-update > "$tmp" 2>/dev/null || dnf_rc=$?
        
        if [[ $dnf_rc -eq 1 ]]; then
            log "DNF check-update encountered an error"
        elif [[ $dnf_rc -eq 100 ]]; then
            log "DNF updates available"
        fi
        
        grep -E '\.(x86_64|noarch|i686|aarch64)' "$tmp" 2>/dev/null \
            | awk '{print $1 " (" $2 ")"}' > "$STATE_DIR/dnf_list" || true
        
        if command -v flatpak >/dev/null 2>&1; then
            flatpak update --appstream --noninteractive >> "$LOGFILE" 2>&1 || true
            flatpak remote-ls --updates --columns=application,version 2>/dev/null \
                | tail -n +2 | awk '{if(NF>=2) print $1 " (" $2 ")"; else print $1}' \
                > "$STATE_DIR/flatpak_list" 2>/dev/null || true
        else
            > "$STATE_DIR/flatpak_list"
        fi
        
        rm -f "$tmp"
    } || {
        rm -f "$tmp"
        return 1
    }
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
    local max_items=$((MAX_NOTIFICATION_ITEMS > 0 ? MAX_NOTIFICATION_ITEMS : 1))
    
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        dnf_count=$(wc -l < "$STATE_DIR/dnf_list")
        dnf_list="📦 Packages ($dnf_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $max_items ]]; do
            dnf_list+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/dnf_list"
        [[ $dnf_count -gt $max_items ]] && dnf_list+="  ... and $((dnf_count - max_items)) more\n"
    fi
    
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
        flatpak_list="🟢 Flatpaks ($flatpak_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $max_items ]]; do
            flatpak_list+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/flatpak_list"
        [[ $flatpak_count -gt $max_items ]] && flatpak_list+="  ... and $((flatpak_count - max_items)) more\n"
    fi
    
    local combined_list=""
    [[ -n "$dnf_list" ]] && combined_list="$dnf_list"
    if [[ -n "$flatpak_list" ]]; then
        [[ -n "$combined_list" ]] && combined_list+="\n"
        combined_list+="$flatpak_list"
    fi
    
    printf '%s\n' "$combined_list"
    printf '%d\n' "$((dnf_count + flatpak_count))" > "$STATE_DIR/update_count"
}

# ================= NOTIFICATIONS =================
notify_pending() {
    local update_list
    local total_count
    
    update_list=$(build_update_list)
    total_count=$(cat "$STATE_DIR/update_count" 2>/dev/null || echo 0)
    
    if [[ -n "$update_list" ]]; then
        notify_with_list "📦 Updates Detected" "Installing $total_count updates...\n\n$update_list" "normal" 0
    else
        notify "Found updates: $total_count items" normal
    fi
    
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        log_raw "Pending packages:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/dnf_list"
    fi
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        log_raw "Pending flatpaks:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/flatpak_list"
    fi
}

notify_complete() {
    local update_list
    local total_count
    
    update_list=$(build_update_list)
    total_count=$(cat "$STATE_DIR/update_count" 2>/dev/null || echo 0)
    
    if [[ -n "$update_list" ]]; then
        notify_with_list "✅ Updates Complete" "Successfully updated $total_count items!\n\n$update_list" "normal" 10000
    else
        notify "Updates completed successfully" normal
    fi
    
    > "$STATE_DIR/dnf_list" 2>/dev/null || true
    > "$STATE_DIR/flatpak_list" 2>/dev/null || true
}

# ================= LOG UPDATED PACKAGES (Direct to HISTORY_LOG) =================
log_updated_packages() {
    local date_str=$(date '+%Y-%m-%d')
    
    # Log DNF packages directly to HISTORY_LOG
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        while IFS= read -r line; do
            printf '%s %s\n' "$date_str" "DNF $line" >> "$HISTORY_LOG"
        done < "$STATE_DIR/dnf_list"
    fi
    
    # Log Flatpak packages directly to HISTORY_LOG
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        while IFS= read -r line; do
            printf '%s %s\n' "$date_str" "Flatpak $line" >> "$HISTORY_LOG"
        done < "$STATE_DIR/flatpak_list"
    fi
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

    check_package_lock || { 
        LAST_DNF_EXIT="locked"
        LAST_FLATPAK_EXIT="skipped"
        return 1 
    }

    local DNF_EXIT=1 FLATPAK_EXIT=1
    local UPDATE_SUCCESS=1
    local TEMP_SYNC_LOG
    TEMP_SYNC_LOG=$(mktemp_safe) || return 1

    sudo -n true 2>/dev/null || {
        log "ERROR: Cannot obtain sudo privileges"
        LAST_DNF_EXIT="no-sudo"
        LAST_FLATPAK_EXIT="no-sudo"
        rm -f "$TEMP_SYNC_LOG"
        return 1
    }

    track_pre_update_state

    (
        while kill -0 "$PPID" 2>/dev/null; do
            sudo -n true 2>/dev/null
            sleep 60
        done
    ) &
    KEEP_ALIVE_PID=$!

    log_raw "=============================="
    log_raw "Starting Nobara System Update"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo nobara-sync cli 2>&1 | tee -a "$LOGFILE" > "$TEMP_SYNC_LOG"
    DNF_EXIT=${PIPESTATUS[0]}
    log_raw "Nobara-sync exit code: $DNF_EXIT"
    
    [[ $DNF_EXIT -eq 124 ]] && log_raw "WARNING: nobara-sync timed out"
    [[ $DNF_EXIT -eq 137 ]] && log_raw "WARNING: nobara-sync was killed"

    log_blank
    log_raw "=============================="
    log_raw "Starting Flatpak Updates"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo flatpak update -y 2>&1 | tee -a "$LOGFILE"
    FLATPAK_EXIT=${PIPESTATUS[0]}
    log_raw "Flatpak (system) exit code: $FLATPAK_EXIT"
    
    [[ $FLATPAK_EXIT -eq 124 ]] && log_raw "WARNING: flatpak (system) timed out"
    
    if [[ $FLATPAK_EXIT -ne 0 ]]; then
        log "Running flatpak repair..."
        sudo flatpak repair --system -y >> "$LOGFILE" 2>&1 || true
        flatpak repair --user -y >> "$LOGFILE" 2>&1 || true
    fi
    
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
    
    if [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -eq 0 ]]; then
        UPDATE_SUCCESS=0
        log_raw "All updates completed successfully"
    elif [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -ne 0 ]]; then
        log_raw "DNF succeeded but Flatpak failed (exit: $FLATPAK_EXIT)"
        alert_failure "Flatpak updates failed"
        UPDATE_SUCCESS=1
    elif [[ $DNF_EXIT -ne 0 && $FLATPAK_EXIT -eq 0 ]]; then
        log_raw "DNF/Nobara-sync failed (exit: $DNF_EXIT)"
        alert_failure "System update failed"
        UPDATE_SUCCESS=1
    else
        log_raw "Both DNF and Flatpak updates failed"
        alert_failure "All updates failed"
        UPDATE_SUCCESS=1
    fi
    
    if [[ $UPDATE_SUCCESS -eq 0 ]]; then
        uname -r > "$POST_UPDATE_KERNEL_FILE" 2>/dev/null || true
        
        # Log individual packages directly to HISTORY_LOG
        log_updated_packages
        
        notify_complete
        
        if [[ "$ENABLE_AUTOREMOVE" == "true" ]]; then
            log "Running post-update cleanup with autoremove..."
            sudo dnf autoremove -y --setopt=clean_requirements_on_remove=False 2>&1 | tee -a "$LOGFILE" || true
        else
            log "Skipping autoremove (disabled)"
        fi
        sudo dnf clean packages 2>&1 | tee -a "$LOGFILE"
        sudo flatpak uninstall --unused -y 2>&1 | tee -a "$LOGFILE"
        flatpak uninstall --user --unused -y 2>&1 | tee -a "$LOGFILE"
        
        log_blank
        log_raw "=============================="
        log_raw "Post-Update Verification"
        log_raw "=============================="
        verify_system_health || true
        
        post_update_security_check
    fi

    rm -f "$TEMP_SYNC_LOG" 2>/dev/null || true
    cleanup_keepalive
    return "$UPDATE_SUCCESS"
}

# ================= ROTATE LOGS =================
rotate_logs() {
    find "$LOG_DIR" -type f -name "*.txt" -mtime +"$MAX_LOG_AGE_DAYS" -delete 2>/dev/null
}

# ================= SMART SLEEP =================
smart_sleep() {
    local duration=$1
    local interval=5
    local elapsed=0

    while (( elapsed < duration )); do
        local remaining=$(( duration - elapsed ))
        if (( remaining < interval )); then
            sleep "$remaining" 2>/dev/null || break
            break
        fi
        sleep "$interval" 2>/dev/null || break
        elapsed=$(( elapsed + interval ))
    done
}

# ================= MAIN LOOP =================
main() {
    trap 'log "Received termination signal, exiting..."; cleanup_keepalive; cleanup_lock; exit 0' SIGTERM SIGINT
    
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
        [[ "$arg" == "--enable-autoremove" ]] && ENABLE_AUTOREMOVE=true && log "AUTOREMOVE ENABLED"
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Auto-update service starting - DRY RUN MODE"
    else
        log "Auto-update service starting"
    fi
    
    if [[ "$ENABLE_AUTOREMOVE" == "true" ]]; then
        log "WARNING: autoremove is ENABLED (high-risk operation)"
    fi

    log "Manual rollback info stored in: $STATE_DIR/"
    log "  - Pre-update kernel: $PRE_UPDATE_KERNEL_FILE"
    log "  - Pre-update transaction: $PRE_UPDATE_TRANSACTION_FILE"

    local retry_delay=60
    local max_delay=3600
    local next_run=$(date +%s)

    while true; do
        if ! check_internet; then
            local offline_start=$(date +%s)
            local sleep_time=60
            local max_sleep=3600
            local notified_prolonged=false
            
            log "🌐 No internet connection detected"
            if can_notify_warning; then
                notify "🌐 No internet connection - updates postponed" "normal" 5000
                update_warning_timestamp
            fi
            
            while ! check_internet; do
                local offline_min=$(( ($(date +%s) - offline_start) / 60 ))
                log "Still offline after ${offline_min} minutes"
                if (( offline_min >= 30 )) && [[ "$notified_prolonged" == "false" ]]; then
                    if can_notify_warning; then
                        notify "Still offline after 30 minutes" "normal" 5000
                        update_warning_timestamp
                        notified_prolonged=true
                    fi
                fi
                smart_sleep "$sleep_time"
                sleep_time=$(( sleep_time * 2 > max_sleep ? max_sleep : sleep_time * 2 ))
            done
            
            log "🌐 Internet connection restored"
            if can_notify_restored; then
                notify "Internet connection restored" "normal" 5000
                update_restored_timestamp
            fi
        fi
        
        if ! check_disk; then 
            log "Disk check failed, retrying in ${retry_delay}s"
            smart_sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi
        
        if ! check_battery; then 
            log "Battery check failed, retrying in ${retry_delay}s"
            smart_sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi

        retry_delay=60
        fetch_pending_updates

        if updates_available; then
            # Get counts BEFORE update
            local dnf_count=0
            local flatpak_count=0
            [[ -s "$STATE_DIR/dnf_list" ]] && dnf_count=$(wc -l < "$STATE_DIR/dnf_list")
            [[ -s "$STATE_DIR/flatpak_list" ]] && flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
            
            # Log the pending summary: OK,DNF:X,FLATPAK:Y
            printf '%s,OK,DNF:%d,FLATPAK:%d\n' "$(date '+%F')" "$dnf_count" "$flatpak_count" >> "$HISTORY_LOG"
            
            notify_pending
            
            if run_updates; then
                # Individual packages are logged inside run_updates() by log_updated_packages()
                
                # Log final state after updates: OK,DNF:0,FLATPAK:0
                printf '%s,OK,DNF:0,FLATPAK:0\n' "$(date '+%F')" >> "$HISTORY_LOG"
                
                log "Update cycle completed successfully"
                update_success_timestamp
                system_up_to_date
                quick_verify
            else
                printf '%s,FAIL,DNF:%s,FLATPAK:%s\n' "$(date '+%F')" "${LAST_DNF_EXIT:-unknown}" "${LAST_FLATPAK_EXIT:-unknown}" >> "$HISTORY_LOG"
                log "Update cycle failed"
            fi
        else
            # No updates available
            printf '%s,OK,DNF:0,FLATPAK:0\n' "$(date '+%F')" >> "$HISTORY_LOG"
            system_up_to_date
            quick_verify
        fi

        rotate_logs
        
        local jitter=$((RANDOM % 120 - 60))
        local adjusted_interval=$((3600 + jitter))
        
        next_run=$((next_run + adjusted_interval))
        local now=$(date +%s)
        if (( next_run < now - adjusted_interval )); then
            log "WARNING: Scheduler falling behind, resetting"
            next_run=$((now + adjusted_interval))
        fi
        
        local sleep_time=$((next_run - now))
        [[ $sleep_time -gt 0 ]] && smart_sleep "$sleep_time"
    done
}

main "$@"
