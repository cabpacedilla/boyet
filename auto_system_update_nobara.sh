#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
SCRIPT_VERSION="v8.3-nobara-hybrid"
STATE_DIR="$HOME/.auto_update_state"
LOG_DIR="$HOME/scriptlogs"
LOGFILE_GENERAL="$LOG_DIR/nobara_update_log.txt"
HISTORY_LOG="$LOG_DIR/update_history.csv"
VERIFICATION_LOG_DIR="$STATE_DIR/verifications"
LOCK_FILE="/tmp/auto_system_update_nobara_$(whoami).lock"
LIST_TMP="/tmp/updateable.txt"

DRY_RUN=false
TIMEOUT_SECONDS=3600
VERIFICATION_TIMEOUT_SECONDS=300
MIN_DISK_SPACE_GB=5
MIN_DISK_SPACE_WARN_GB=10
MIN_BATTERY_PCT=30
MAX_LOG_AGE_DAYS=30
MAX_VERIFICATION_AGE_DAYS=90
MAX_HISTORY_LINES=1000
MAX_LOGFILE_BYTES=$((10 * 1024 * 1024))
MAX_NOTIFICATION_ITEMS=30
TRACK_PACKAGE_DETAILS=true
AUTO_ROLLBACK_ENABLED=true
ROLLBACK_SAFETY_LEVEL="comprehensive"

FAILURE_STREAK=0
MAX_FAILURES_BEFORE_ESCALATION=3
LAST_EXIT_REASON="none"

# Critical services that trigger automatic rollback
CRITICAL_SERVICES="NetworkManager.service|sshd.service|dbus.service|systemd-logind.service"

# Rollback confirmation settings
ROLLBACK_REQUIRES_CONFIRMATION=true
ROLLBACK_CONFIRMATION_TIMEOUT=300
ROLLBACK_NOTIFICATION_ACTIONS=true

mkdir -p "$STATE_DIR" "$LOG_DIR" "$VERIFICATION_LOG_DIR" "$(dirname "$LOGFILE_GENERAL")" || {
    echo "FATAL: Cannot create required directories" >&2
    exit 1
}

rm -f "$STATE_DIR/last_result" 2>/dev/null || true

# Initialize CSV with header
if [[ ! -f "$HISTORY_LOG" ]]; then
    echo '"date","status","update_method","exit_code","flatpak","reason","packages_updated","flatpaks_updated","rollback_performed","rollback_risks"' > "$HISTORY_LOG"
fi

# ================= LOCK WITH PID TRACKING =================
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Another instance is already running" >> "$LOGFILE_GENERAL"
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# ================= GLOBAL CLEANUP =================
RUNNING=true
TEMP_FILES=()
KEEP_ALIVE_PID=""

cleanup_temp_files() {
    for file in "${TEMP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
    rm -f "$LIST_TMP" 2>/dev/null || true
}

cleanup_keepalive() {
    if [[ -n "$KEEP_ALIVE_PID" ]]; then
        kill "$KEEP_ALIVE_PID" 2>/dev/null || true
        KEEP_ALIVE_PID=""
    fi
}

cleanup() {
    # Only remove if it's our PID
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    cleanup_keepalive
    cleanup_temp_files
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

trap cleanup EXIT
trap 'RUNNING=false' INT TERM

# ================= LOG =================
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE_GENERAL"
}

log_raw() {
    echo "$*" | tee -a "$LOGFILE_GENERAL"
}

log_blank() {
    echo "" >> "$LOGFILE_GENERAL"
    echo ""
}

# ================= NOTIFY =================
notify() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    notify-send -u "${2:-normal}" -t 0 "Auto Update" "$1"
}

notify_with_list() {
    local title="$1"
    local body="$2"
    local urgency="${3:-normal}"
    
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    
    local formatted_body="${body//\\n/$'\n'}"
    if [[ ${#formatted_body} -gt 2000 ]]; then
        formatted_body="${formatted_body:0:2000}..."
    fi
    notify-send -u "$urgency" -t 0 "Auto Update: $title" "$formatted_body"
}

alert_failure() {
    log "ALERT: $1"
    notify "$1" critical
}

# ================= DEPENDENCY CHECK =================
for cmd in dnf rpm systemctl journalctl flatpak nobara-sync nobara-updater; do
    command -v "$cmd" >/dev/null || {
        echo "FATAL: Missing required command: $cmd" >&2
        exit 1
    }
done

# ================= SAFETY CHECKS =================
check_dnf_lock() {
    if pgrep -x dnf >/dev/null || pgrep -x rpm >/dev/null; then
        log "DNF/RPM already running, skipping..."
        return 1
    fi
    return 0
}

check_network() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        log "Network connectivity check failed"
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
    local battery_ok=true
    
    local nullglob_was_set=false
    shopt -q nullglob && nullglob_was_set=true
    shopt -s nullglob
    
    for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/BATT*; do
        [[ -f "$bat/capacity" ]] || continue
        battery_found=true
        local cap status
        cap=$(<"$bat/capacity")
        status=$(<"$bat/status")

        if [[ ! "$cap" =~ ^[0-9]+$ ]]; then
            log "Unexpected battery capacity value: '$cap'"
            if ! $nullglob_was_set; then
                shopt -u nullglob
            fi
            return 1
        fi

        if [[ "$status" != "Charging" && "$status" != "Full" && "$cap" -lt "$MIN_BATTERY_PCT" ]]; then
            log "Low battery: ${cap}% (min ${MIN_BATTERY_PCT}%), status: $status"
            battery_ok=false
        fi
    done
    
    if ! $nullglob_was_set; then
        shopt -u nullglob
    fi

    if ! $battery_found && ! $BATTERY_WARNING_LOGGED; then
        log "No battery detected (desktop mode)"
        BATTERY_WARNING_LOGGED=true
    fi
    
    if [[ "$battery_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ================= KERNEL HELPERS (FIXED) =================
get_latest_kernel() {
    local kernel=""
    
    # Method 1: Try grubby to get the default boot kernel
    if command -v grubby >/dev/null 2>&1; then
        local default_kernel
        default_kernel=$(grubby --default-kernel 2>/dev/null || true)
        if [[ -n "$default_kernel" && "$default_kernel" != "/boot" ]]; then
            # Extract kernel version from path like /boot/vmlinuz-6.19.11-201.nobara.fc43.x86_64
            kernel=$(basename "$default_kernel" 2>/dev/null | sed 's/^vmlinuz-//' || true)
            if [[ -n "$kernel" && "$kernel" != "/boot" && "$kernel" != "vmlinuz"* ]]; then
                log "DEBUG: get_latest_kernel from grubby: $kernel"
                echo "$kernel"
                return 0
            fi
        fi
    fi
    
    # Method 2: Fallback to most recently installed kernel via rpm
    local kernel_pkg
    kernel_pkg=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' || true)
    if [[ -n "$kernel_pkg" ]]; then
        kernel=$(echo "$kernel_pkg" | sed 's/^kernel-//' || true)
        if [[ -n "$kernel" && "$kernel" != "kernel"* ]]; then
            log "DEBUG: get_latest_kernel from rpm: $kernel"
            echo "$kernel"
            return 0
        fi
    fi
    
    # Method 3: Try reading from /boot directory
    if [[ -d /boot ]]; then
        local latest_vmlinuz
        latest_vmlinuz=$(ls -t /boot/vmlinuz-* 2>/dev/null | head -n1 || true)
        if [[ -n "$latest_vmlinuz" ]]; then
            kernel=$(basename "$latest_vmlinuz" | sed 's/^vmlinuz-//' || true)
            if [[ -n "$kernel" ]]; then
                log "DEBUG: get_latest_kernel from /boot: $kernel"
                echo "$kernel"
                return 0
            fi
        fi
    fi
    
    # Method 4: Final fallback to running kernel
    kernel=$(uname -r)
    log "DEBUG: get_latest_kernel fallback to running: $kernel"
    echo "$kernel"
}

get_running_kernel() {
    local kernel
    kernel=$(uname -r)
    # Remove any extra suffixes for comparison
    kernel=$(echo "$kernel" | sed 's/\.x86_64$//' | sed 's/\.fc[0-9]\+\.x86_64$//' | sed 's/\.fc[0-9]\+$//')
    echo "$kernel"
}

# ================= SERVICE BASELINE TRACKING =================
save_service_baseline() {
    if [[ "$DRY_RUN" != "true" ]]; then
        systemctl list-units --state=running --type=service --no-legend 2>/dev/null | \
            awk '{print $1}' | sort > "$STATE_DIR/services_running_before.txt" || true
        
        systemctl list-units --state=failed --type=service --no-legend 2>/dev/null | \
            awk '{print $1}' | sort > "$STATE_DIR/services_failed_before.txt" || true
        
        systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | \
            awk '{print $1}' | sort > "$STATE_DIR/services_enabled_before.txt" || true
        
        log "Saved service baseline before update"
    fi
}

check_service_changes() {
    local new_failures=""
    local recovered_services=""
    local has_critical_failure=false
    local notification_body=""
    
    systemctl list-units --state=failed --type=service --no-legend 2>/dev/null | \
        awk '{print $1}' | sort > "$STATE_DIR/services_failed_after.txt" || true
    
    systemctl list-units --state=running --type=service --no-legend 2>/dev/null | \
        awk '{print $1}' | sort > "$STATE_DIR/services_running_after.txt" || true
    
    if [[ -f "$STATE_DIR/services_failed_before.txt" ]]; then
        new_failures=$(comm -23 "$STATE_DIR/services_failed_after.txt" "$STATE_DIR/services_failed_before.txt" || true)
        recovered_services=$(comm -13 "$STATE_DIR/services_failed_after.txt" "$STATE_DIR/services_failed_before.txt" || true)
    else
        new_failures=$(cat "$STATE_DIR/services_failed_after.txt" 2>/dev/null || true)
    fi
    
    if [[ -n "$new_failures" ]]; then
        notification_body="⚠️ New service failures detected:\\n\\n"
        echo "$new_failures" | while read -r service; do
            [[ -z "$service" ]] && continue
            notification_body+="  • $service\\n"
            log "NEW service failure: $service"
            
            if echo "$service" | grep -qiE "$CRITICAL_SERVICES"; then
                log "CRITICAL: New critical service failure: $service"
                has_critical_failure=true
            fi
        done
        
        if [[ -n "$notification_body" ]]; then
            if $has_critical_failure; then
                notify_with_list "Service Failures Detected" "$notification_body" "critical"
            else
                notify_with_list "Service Failures Detected" "$notification_body" "normal"
            fi
        fi
    fi
    
    if [[ -n "$recovered_services" ]]; then
        local recovery_msg="✅ Services recovered (previously failed, now running):\\n\\n"
        echo "$recovered_services" | while read -r service; do
            [[ -z "$service" ]] && continue
            recovery_msg+="  • $service\\n"
            log "Service recovered: $service"
        done
        notify_with_list "Services Recovered" "$recovery_msg" "normal"
    fi
    
    if $has_critical_failure; then
        return 0
    else
        return 1
    fi
}

# ================= DETAILED PACKAGE TRACKING =================
save_package_snapshot() {
    if [[ "$DRY_RUN" != "true" ]]; then
        rpm -qa > "$STATE_DIR/packages_before.txt" 2>/dev/null || true
        log "Saved package snapshot before update"
    fi
}

# ================= FETCH UPDATES (NOBARA WAY) =================
fetch_pending_updates() {
    log "Checking for updates via nobara-updater..."
    
    # Nobara command #1: check-updates
    sudo nobara-updater check-updates >> "$LOGFILE_GENERAL" 2>&1 || true
    
    # Also get DNF updates for detailed listing
    sudo dnf check-update > "$LIST_TMP" 2>/dev/null || true
    PENDING_DNF=$(grep -E '\.(x86_64|noarch|i686)' "$LIST_TMP" 2>/dev/null | awk '{print $1 " (" $2 ")"}' || echo "")
    
    # Flatpak updates
    PENDING_FP=$(flatpak remote-ls --updates 2>/dev/null | tail -n +2 | awk '{if(NF>=2 && $2) print $1 " (" $2 ")"; else print $1}' || echo "")
    
    # Save to state files
    if [[ -n "$PENDING_DNF" ]]; then
        echo "$PENDING_DNF" > "$STATE_DIR/dnf_list"
    else
        > "$STATE_DIR/dnf_list"
    fi
    
    if [[ -n "$PENDING_FP" ]]; then
        echo "$PENDING_FP" > "$STATE_DIR/flatpak_list"
    else
        > "$STATE_DIR/flatpak_list"
    fi
}

updates_available() {
    [[ -s "$STATE_DIR/dnf_list" || -s "$STATE_DIR/flatpak_list" ]]
}

# ================= NOTIFICATIONS WITH PACKAGE LISTS =================
notify_pending() {
    local pkg_count=0
    local flatpak_count=0
    local notify_msg=""

    [[ -s "$STATE_DIR/dnf_list" ]] && pkg_count=$(wc -l < "$STATE_DIR/dnf_list")
    [[ -s "$STATE_DIR/flatpak_list" ]] && flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
    local total_count=$((pkg_count + flatpak_count))

    if [[ $pkg_count -gt 0 ]]; then
        notify_msg="📦 Packages ($pkg_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $MAX_NOTIFICATION_ITEMS ]]; do
            notify_msg+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/dnf_list"
        if [[ $pkg_count -gt $MAX_NOTIFICATION_ITEMS ]]; then
            notify_msg+="  ... and $((pkg_count - MAX_NOTIFICATION_ITEMS)) more\n"
        fi
    fi
    
    if [[ $flatpak_count -gt 0 ]]; then
        if [[ -n "$notify_msg" ]]; then
            notify_msg+="\n"
        fi
        notify_msg+="🟢 Flatpaks ($flatpak_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $MAX_NOTIFICATION_ITEMS ]]; do
            notify_msg+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/flatpak_list"
        if [[ $flatpak_count -gt $MAX_NOTIFICATION_ITEMS ]]; then
            notify_msg+="  ... and $((flatpak_count - MAX_NOTIFICATION_ITEMS)) more\n"
        fi
    fi
    
    if [[ -n "$notify_msg" ]]; then
        notify_with_list "Updates Detected" "$notify_msg" "normal"
    else
        notify "Found updates: $pkg_count packages, $flatpak_count flatpaks" normal
    fi

    if [[ $pkg_count -gt 0 ]]; then
        log_raw "Pending packages:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/dnf_list"
    fi
    if [[ $flatpak_count -gt 0 ]]; then
        log_raw "Pending flatpaks:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/flatpak_list"
    fi
}

notify_complete() {
    local pkg_count=0
    local flatpak_count=0
    local notify_msg=""

    [[ -s "$STATE_DIR/dnf_list" ]] && pkg_count=$(wc -l < "$STATE_DIR/dnf_list")
    [[ -s "$STATE_DIR/flatpak_list" ]] && flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
    local total_count=$((pkg_count + flatpak_count))

    if [[ $pkg_count -gt 0 ]]; then
        notify_msg="📦 Packages ($pkg_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $MAX_NOTIFICATION_ITEMS ]]; do
            notify_msg+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/dnf_list"
    fi
    
    if [[ $flatpak_count -gt 0 ]]; then
        if [[ -n "$notify_msg" ]]; then
            notify_msg+="\n"
        fi
        notify_msg+="🟢 Flatpaks ($flatpak_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $MAX_NOTIFICATION_ITEMS ]]; do
            notify_msg+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/flatpak_list"
    fi
    
    if [[ -n "$notify_msg" ]]; then
        notify_with_list "Updates Complete" "Successfully updated $total_count items:\n\n$notify_msg" "normal"
    else
        notify "Updates completed successfully" normal
    fi
}

# ================= POST-UPDATE VERIFICATION =================
verify_system_health() {
    local start_time=$(date +%s)
    local verification_log="$VERIFICATION_LOG_DIR/verification_$(date +%F-%H%M%S).log"
    local verification_failed=0
    local all_changes=""
    local change_count=0
    local all_critical=""
    local error_count=0
    local has_critical_service_failure=false

    log "Running post-update system verification..."

    if check_service_changes; then
        has_critical_service_failure=true
        verification_failed=1
    fi

    log "Verifying package integrity (this may take up to ${VERIFICATION_TIMEOUT_SECONDS}s)..."
    local rpm_cmd="rpm -Va"
    if command -v ionice >/dev/null; then
        rpm_cmd="ionice -c3 nice -n 19 $rpm_cmd"
    else
        rpm_cmd="nice -n 19 $rpm_cmd"
    fi
    
    local rpm_full
    rpm_full=$(timeout "$VERIFICATION_TIMEOUT_SECONDS" bash -c "$rpm_cmd" 2>/dev/null || true)
    all_changes=$(echo "$rpm_full" | grep -v "^..5" || true)
    
    if [[ -n "$all_changes" ]]; then
        change_count=$(echo "$all_changes" | wc -l)
    else
        change_count=0
    fi

    all_critical=$(timeout "$VERIFICATION_TIMEOUT_SECONDS" journalctl -b -p 3 --no-pager 2>/dev/null || true)
    if [[ -n "$all_critical" ]]; then
        error_count=$(echo "$all_critical" | wc -l)
    else
        error_count=0
    fi

    {
        echo "=========================================="
        echo "Nobara Post-Update Verification Report"
        echo "=========================================="
        echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Host: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo ""

        echo "1. CHECKING FAILED SERVICES"
        echo "---------------------------"
        local failed_services
        failed_services=$(systemctl --failed --no-legend 2>/dev/null || true)
        if [[ -n "$failed_services" ]]; then
            echo "FAILED SERVICES DETECTED:"
            echo "$failed_services"
            verification_failed=1
        else
            echo "All services running normally."
        fi
        echo ""

        echo "2. VERIFYING PACKAGE INTEGRITY"
        echo "-----------------------------"
        if [[ $change_count -eq 0 ]]; then
            echo "All package files verified."
        else
            echo "File changes detected: $change_count files"
            echo "$all_changes" | head -50
            if [[ $change_count -gt 100 ]]; then
                echo "WARNING: Large number of changes - possible corruption!"
                verification_failed=1
            fi
        fi
        echo ""

        echo "3. CHECKING FILESYSTEM STATUS"
        echo "----------------------------"
        if findmnt -n -o OPTIONS / 2>/dev/null | grep -q "ro"; then
            echo "Root filesystem is mounted read-only!"
            verification_failed=1
        else
            echo "Root filesystem writable."
        fi
        echo ""

        echo "4. CHECKING KERNEL CONSISTENCY"
        echo "-----------------------------"
        local latest_kernel running_kernel
        latest_kernel=$(get_latest_kernel)
        running_kernel=$(uname -r)
        if [[ "$latest_kernel" != "$running_kernel" ]]; then
            echo "KERNEL UPDATE PENDING REBOOT"
            echo "   Running: $running_kernel"
            echo "   Installed: $latest_kernel"
            echo "   Reboot required for new kernel to take effect."
        else
            echo "Kernel version consistent: $running_kernel"
        fi
        echo ""

        echo "5. TESTING NETWORK CONNECTIVITY"
        echo "------------------------------"
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            echo "Network connectivity OK."
        elif ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
            echo "Network connectivity OK (alternate DNS)."
        else
            echo "Network connectivity issue detected."
        fi
        echo ""

        echo "6. CHECKING CRITICAL ERROR LOGS"
        echo "------------------------------"
        if [[ $error_count -eq 0 ]]; then
            echo "No critical errors found."
        else
            echo "Critical errors since boot: $error_count (first 20 lines)"
            echo "$all_critical" | head -20
        fi
        echo ""

        echo "7. CHECKING DISK SPACE"
        echo "---------------------"
        local avail
        avail=$(df -BG / | awk 'NR==2 {print $4}' | tr -d G)
        echo "Available disk space: ${avail}GB"
        if [[ "$avail" -lt "$MIN_DISK_SPACE_WARN_GB" ]]; then
            echo "Low disk space after update - consider cleanup"
        fi
        echo ""

        echo "8. MEMORY STATUS"
        echo "---------------"
        while IFS= read -r line; do
            echo "   $line"
        done < <(free -h | grep -E "Mem|Swap")
        echo ""

        echo "=========================================="
        echo "Verification completed at $(date '+%Y-%m-%d %H:%M:%S')"
        local duration=$(( $(date +%s) - start_time ))
        echo "Verification took ${duration} seconds"
        if [[ $verification_failed -eq 1 ]]; then
            echo "STATUS: ISSUES DETECTED"
        else
            echo "STATUS: HEALTHY"
        fi
        echo "=========================================="

    } > "$verification_log" 2>&1

    cat "$verification_log" >> "$LOGFILE_GENERAL"

    if [[ $verification_failed -eq 1 ]]; then
        log "Post-update verification found issues - see $verification_log"
        
        if $has_critical_service_failure; then
            log "CRITICAL: New critical service failures detected - check verification log"
            notify "Critical: New service failures after update - check log" critical
        else
            notify "Post-update issues detected - check verification log" normal
        fi
    else
        log "Post-update verification passed - see $verification_log"
    fi

    find "$VERIFICATION_LOG_DIR" -type f -name "verification_*.log" -mtime +"$MAX_VERIFICATION_AGE_DAYS" -delete 2>/dev/null || true

    return $verification_failed
}

# ================= QUICK VERIFICATION (FIXED - USES RPM ONLY) =================
quick_verify() {
    local issues_found=0
    local reboot_required=false
    local reboot_reason=""
    
    # Get latest kernel from RPM (most reliable - avoids grubby issues)
    local latest_kernel=""
    local kernel_pkg
    kernel_pkg=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' || true)
    if [[ -n "$kernel_pkg" ]]; then
        latest_kernel=$(echo "$kernel_pkg" | sed 's/^kernel-//' || true)
    fi
    
    # Get running kernel
    local running_kernel
    running_kernel=$(uname -r)
    
    # Extract base versions for comparison (remove architecture and release suffixes)
    local latest_base=""
    local running_base=""
    
    if [[ -n "$latest_kernel" ]]; then
        # Remove .x86_64 and .fcXX suffixes for clean comparison
        latest_base=$(echo "$latest_kernel" | sed 's/\.x86_64$//' | sed 's/\.fc[0-9]\+\.x86_64$//' | sed 's/\.fc[0-9]\+$//')
    fi
    running_base=$(echo "$running_kernel" | sed 's/\.x86_64$//' | sed 's/\.fc[0-9]\+\.x86_64$//' | sed 's/\.fc[0-9]\+$//')
    
    log "DEBUG: latest_kernel='$latest_kernel' latest_base='$latest_base' running='$running_kernel' running_base='$running_base'"
    
    # Compare the base versions
    if [[ -n "$latest_base" && "$latest_base" != "$running_base" ]]; then
        reboot_reason="Kernel updated from $running_base to $latest_base"
        reboot_required=true
    fi
    
    # Handle reboot notification - use kernel version as unique identifier
    if [[ "$reboot_required" == "true" ]]; then
        # Use the target kernel base version in the flag filename
        local reboot_flag="$STATE_DIR/reboot_notified_kernel_${latest_base}"
        
        if [[ ! -f "$reboot_flag" ]]; then
            log "Quick check: Reboot required - $reboot_reason"
            notify "Reboot recommended - $reboot_reason" normal
            touch "$reboot_flag"
            
            # Clean up old notification files (older than 7 days)
            find "$STATE_DIR" -maxdepth 1 -name "reboot_notified_kernel_*" -mtime +7 -delete 2>/dev/null || true
        else
            # Already notified for this kernel - suppress duplicate
            log "Quick check: Reboot still required - $reboot_reason (already notified - suppression active)"
        fi
        issues_found=1
    else
        # No reboot needed - clean up ALL reboot notification flags
        rm -f "$STATE_DIR"/reboot_notified_kernel_* 2>/dev/null || true
    fi
    
    # Check for failed services (with per-day notification limit to avoid spam)
    if systemctl --failed --no-legend 2>/dev/null | grep -q .; then
        local service_failure_file="$STATE_DIR/service_failure_notified_$(date +%Y%m%d)"
        if [[ ! -f "$service_failure_file" ]]; then
            local failed_count
            failed_count=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
            log "Quick check: $failed_count failed services detected"
            notify "System degraded - $failed_count failed services. Check 'systemctl --failed'" critical
            touch "$service_failure_file"
            find "$STATE_DIR" -maxdepth 1 -name "service_failure_notified_*" -mtime +7 -delete 2>/dev/null || true
        fi
        issues_found=1
    else
        find "$STATE_DIR" -maxdepth 1 -name "service_failure_notified_*" -delete 2>/dev/null || true
    fi
    
    return $issues_found
}

# ================= RUN UPDATES =================
LAST_DNF_EXIT=""
LAST_FLATPAK_EXIT=""
REBOOT_REQUIRED=false

run_updates() {
    local start_time=$(date +%s)
    
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

    local UPDATE_SUCCESS=1

    save_package_snapshot
    save_service_baseline

    # Start keep-alive loop
    keep_sudo_alive() {
        while true; do
            sudo -n true 2>/dev/null || true
            sleep 60
        done
    }
    keep_sudo_alive &
    KEEP_ALIVE_PID=$!

    log_raw "=============================="
    log_raw "Starting Nobara System Update"
    log_raw "=============================="
    
    # Nobara command #2: nobara-sync cli
    timeout "$TIMEOUT_SECONDS" sudo nobara-sync cli 2>&1 | tee -a "$LOGFILE_GENERAL"
    local NOBARA_EXIT=${PIPESTATUS[0]}
    log_raw "Nobara-sync exit code: $NOBARA_EXIT"
    
    # Flatpak updates
    log_blank
    log_raw "=============================="
    log_raw "Starting Flatpak Updates"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo flatpak update -y 2>&1 | tee -a "$LOGFILE_GENERAL"
    local FLATPAK_EXIT=${PIPESTATUS[0]}
    log_raw "Flatpak (system) exit code: $FLATPAK_EXIT"
    
    if [[ $FLATPAK_EXIT -eq 0 ]]; then
        timeout "$TIMEOUT_SECONDS" flatpak update --user -y 2>&1 | tee -a "$LOGFILE_GENERAL"
        FLATPAK_EXIT=${PIPESTATUS[0]}
        log_raw "Flatpak (user) exit code: $FLATPAK_EXIT"
    fi

    LAST_DNF_EXIT="$NOBARA_EXIT"
    LAST_FLATPAK_EXIT="$FLATPAK_EXIT"

    local duration=$(( $(date +%s) - start_time ))
    log_blank
    log_raw "=============================="
    log_raw "Update Summary"
    log_raw "=============================="
    log_raw "Update completed in ${duration} seconds"

    if [[ $NOBARA_EXIT -eq 0 && $FLATPAK_EXIT -eq 0 ]]; then
        UPDATE_SUCCESS=0
        log_raw "Updates completed successfully"
        LAST_EXIT_REASON="success"

        log "Running post-update cleanup..."
        sudo dnf autoremove -y 2>&1 | tee -a "$LOGFILE_GENERAL"
        sudo dnf clean packages 2>&1 | tee -a "$LOGFILE_GENERAL"
        sudo flatpak uninstall --unused -y 2>&1 | tee -a "$LOGFILE_GENERAL"
        flatpak uninstall --user --unused -y 2>&1 | tee -a "$LOGFILE_GENERAL"

        log_blank
        log_raw "=============================="
        log_raw "Post-Update Verification"
        log_raw "=============================="
        verify_system_health || true
        
        # Log to History CSV
        if [[ -s "$STATE_DIR/dnf_list" ]]; then
            cat "$STATE_DIR/dnf_list" | awk -v dt="$(date '+%Y-%m-%d')" 'NF {print dt ",DNF," $0}' >> "$HISTORY_LOG"
        fi
        if [[ -s "$STATE_DIR/flatpak_list" ]]; then
            cat "$STATE_DIR/flatpak_list" | awk -v dt="$(date '+%Y-%m-%d')" 'NF {print dt ",Flatpak," $0}' >> "$HISTORY_LOG"
        fi
    else
        log_raw "Updates failed (Nobara: $NOBARA_EXIT, Flatpak: $FLATPAK_EXIT)"
        LAST_EXIT_REASON="update_failure"
        notify_with_list "❌ Update Failed" "Nobara exit: $NOBARA_EXIT\nFlatpak exit: $FLATPAK_EXIT\nCheck log: $LOGFILE_GENERAL" "critical"
    fi

    # Log to history CSV summary
    (
        flock -x 200
        printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
            "$(date '+%Y-%m-%d')" \
            "$([ $UPDATE_SUCCESS -eq 0 ] && echo "OK" || echo "FAIL")" \
            "nobara-sync" \
            "${LAST_DNF_EXIT}" \
            "${LAST_FLATPAK_EXIT}" \
            "${LAST_EXIT_REASON}" \
            "0" \
            "0" \
            "none" >> "$HISTORY_LOG"
    ) 200>> "$HISTORY_LOG"

    cleanup_keepalive
    return "$UPDATE_SUCCESS"
}

# ================= ROTATE LOGS =================
rotate_logs() {
    find "$LOG_DIR" -type f \( -name "*.txt" -o -name "*.csv" \) -mtime +"$MAX_LOG_AGE_DAYS" -delete 2>/dev/null
    
    find "$VERIFICATION_LOG_DIR" -type f -name "verification_*.log" -mtime +"$MAX_VERIFICATION_AGE_DAYS" -delete 2>/dev/null || true
    
    if [[ -f "$LOGFILE_GENERAL" ]]; then
        local size
        size=$(stat -c %s "$LOGFILE_GENERAL" 2>/dev/null || stat -f %z "$LOGFILE_GENERAL" 2>/dev/null || echo 0)
        if [[ "$size" -gt "$MAX_LOGFILE_BYTES" ]]; then
            tail -c "$MAX_LOGFILE_BYTES" "$LOGFILE_GENERAL" > "$LOGFILE_GENERAL.tmp" && \
                mv "$LOGFILE_GENERAL.tmp" "$LOGFILE_GENERAL" || \
                rm -f "$LOGFILE_GENERAL.tmp"
            log "Trimmed main log file to ${MAX_LOGFILE_BYTES} bytes"
        fi
    fi
    
    if [[ -f "$HISTORY_LOG" ]]; then
        rm -f "$HISTORY_LOG.tmp"
        if [[ $(wc -l < "$HISTORY_LOG") -gt "$MAX_HISTORY_LINES" ]]; then
            tail -n "$MAX_HISTORY_LINES" "$HISTORY_LOG" > "$HISTORY_LOG.tmp" && \
                mv "$HISTORY_LOG.tmp" "$HISTORY_LOG" || \
                rm -f "$HISTORY_LOG.tmp"
            log "Trimmed history log to $MAX_HISTORY_LINES lines"
        fi
    fi
}

# ================= MAIN LOOP =================
main() {
    for arg in "$@"; do
        if [[ "$arg" == "--dry-run" ]]; then
            DRY_RUN=true
            break
        fi
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        log "Auto-update service starting (PID $$) - DRY RUN MODE - $SCRIPT_VERSION"
    else
        log "Auto-update service starting (PID $$) - $SCRIPT_VERSION"
        log "Host: $(hostname)"
        log "Update method: nobara-sync cli"
        log "Max notification items: $MAX_NOTIFICATION_ITEMS"
        log "Rollback safety level: $ROLLBACK_SAFETY_LEVEL"
    fi

    local disk_retry_delay=60
    local battery_retry_delay=60
    local max_delay=3600

    while [[ "$RUNNING" == "true" ]]; do
        if ! check_network; then
            log "Network check failed, will retry next cycle"
            sleep 300 &
            wait $! || true
            continue
        fi
        
        if ! check_disk; then
            log "Disk check failed, retrying in ${disk_retry_delay}s"
            sleep "$disk_retry_delay"
            disk_retry_delay=$(( disk_retry_delay * 2 > max_delay ? max_delay : disk_retry_delay * 2 ))
            continue
        fi
        disk_retry_delay=60

        if ! check_battery; then
            log "Battery check failed, retrying in ${battery_retry_delay}s"
            sleep "$battery_retry_delay"
            battery_retry_delay=$(( battery_retry_delay * 2 > max_delay ? max_delay : battery_retry_delay * 2 ))
            continue
        fi
        battery_retry_delay=60

        fetch_pending_updates

        if updates_available; then
            notify_pending
            if run_updates; then
                notify_complete
                log "Update cycle completed successfully"
                FAILURE_STREAK=0
            else
                log "Update cycle failed"
                FAILURE_STREAK=$((FAILURE_STREAK + 1))
                if [[ $FAILURE_STREAK -ge $MAX_FAILURES_BEFORE_ESCALATION ]]; then
                    log "CRITICAL: $FAILURE_STREAK consecutive update failures"
                    notify "Multiple update failures - manual intervention may be required" critical
                    FAILURE_STREAK=0
                fi
            fi
        else
            log "System is up to date."
            notify "System is up to date." normal
            quick_verify
            FAILURE_STREAK=0
        fi

        rotate_logs
        cleanup_temp_files
        
        sleep 1h &
        wait $! || true
    done
    
    log "Auto-update service shutting down gracefully"
}

# Run main function
main "$@"
