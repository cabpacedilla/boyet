#!/usr/bin/env bash
set -euo pipefail

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

mkdir -p "$STATE_DIR" "$LOG_DIR" "$VERIFICATION_LOG_DIR" || {
    echo "FATAL: Cannot create required directories" >&2
    exit 1
}

# Clean up stale files from previous versions
rm -f "$STATE_DIR/last_result" 2>/dev/null || true

# ================= LOG =================
log() {
    echo "$(date '+%F %T') - $*" | tee -a "$LOGFILE"
}

# Raw log without timestamp (for banners)
log_raw() {
    echo "$*" | tee -a "$LOGFILE"
}

# Bash builtin echo, no subshell
log_blank() {
    echo "" >> "$LOGFILE"
    echo ""
}

# ================= NOTIFY =================
notify() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    notify-send -u "${2:-normal}" -t 0 "Auto Update" "$1"
}

alert_failure() {
    log "ALERT: $1"
    notify "$1" critical
}

# ================= GLOBAL CLEANUP FOR KEEP-ALIVE =================
# IMPORTANT: Must be defined before trap registration
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
#~ exec 9>"$LOCK_FILE"
#~ flock -n 9 || { 
    #~ # LOGFILE exists because mkdir -p ran earlier
    #~ echo "$(date '+%F %T') - Already running" | tee -a "$LOGFILE"
    #~ exit 1
#~ }
#~ # Single trap handles all cleanup (cleanup functions already defined)
#~ trap 'cleanup_lock; cleanup_keepalive' EXIT INT TERM

# ================= SAFETY =================
# Note: check_dnf_lock has a TOCTOU race condition (process could start between check and execution)
# This is acceptable because nobara-sync handles its own locking internally
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
    
    # Validate that avail is a number (defensive guard against unexpected df output)
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

# Track if battery warning has been logged to avoid log spam
BATTERY_WARNING_LOGGED=false

# Returns 0 if battery is OK (charging OR above MIN_BATTERY_PCT), 1 if critical
# On systems without battery, always returns 0
check_battery() {
    local battery_found=false
    for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/BATT*; do
        [[ -f "$bat/capacity" ]] || continue
        battery_found=true
        local cap status
        cap=$(<"$bat/capacity")
        status=$(<"$bat/status")
        
        # Validate battery capacity is a number (defensive guard)
        if [[ ! "$cap" =~ ^[0-9]+$ ]]; then
            log "Unexpected battery capacity value: '$cap'"
            return 1
        fi
        
        if [[ "$status" != "Charging" && "$cap" -lt "$MIN_BATTERY_PCT" ]]; then
            log "Low battery: ${cap}% (min ${MIN_BATTERY_PCT}%), not charging"
            return 1
        fi
    done
    
    if ! $battery_found && ! $BATTERY_WARNING_LOGGED; then
        log "No battery detected (desktop mode)"
        BATTERY_WARNING_LOGGED=true
    fi
    return 0
}

# ================= POST-UPDATE VERIFICATION =================
# Note: verification failure is informational only - does not affect update success status
verify_system_health() {
    local verification_log="$VERIFICATION_LOG_DIR/verification_$(date +%F-%H%M%S).log"
    local verification_failed=0
    local all_changes=""
    local change_count=0
    local all_critical=""
    local error_count=0
    
    log "Running post-update system verification..."
    
    # Capture rpm verification once (it's expensive - can take 30-60 seconds)
    log "Verifying package integrity (this may take up to a minute)..."
    all_changes=$(rpm -Va 2>/dev/null | grep -v "^..5" || true)
    
    # Count changes correctly (empty string = 0 changes)
    if [[ -n "$all_changes" ]]; then
        change_count=$(echo "$all_changes" | wc -l)
    else
        change_count=0
    fi
    
    # Capture journal critical errors once
    all_critical=$(journalctl -b -p 3 --no-pager 2>/dev/null || true)
    if [[ -n "$all_critical" ]]; then
        error_count=$(echo "$all_critical" | wc -l)
    else
        error_count=0
    fi
    
    # Write verification report directly to file
    {
        echo "=========================================="
        echo "Fedora Post-Update Verification Report"
        echo "=========================================="
        echo "Time: $(date '+%F %T')"
        echo "Host: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo ""
        
        # 1. Check for failed systemd services (most critical)
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
        
        # 2. Verify package integrity
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
        
        # 3. Check filesystem writability
        echo "3. CHECKING FILESYSTEM STATUS"
        echo "----------------------------"
        if findmnt -n -o OPTIONS / 2>/dev/null | grep -q "ro"; then
            echo "Root filesystem is mounted read-only!"
            verification_failed=1
        else
            echo "Root filesystem writable."
        fi
        echo ""
        
        # 4. Check kernel version vs booted kernel
        echo "4. CHECKING KERNEL CONSISTENCY"
        echo "-----------------------------"
        local installed_kernel
        local running_kernel
        installed_kernel=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-//')
        running_kernel=$(uname -r)
        if [[ "$installed_kernel" != "$running_kernel" ]]; then
            echo "KERNEL UPDATE PENDING REBOOT"
            echo "   Running: $running_kernel"
            echo "   Installed: $installed_kernel"
            echo "   Reboot required for new kernel to take effect."
        else
            echo "Kernel version consistent: $running_kernel"
        fi
        echo ""
        
        # 5. Network connectivity test
        echo "5. TESTING NETWORK CONNECTIVITY"
        echo "------------------------------"
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            echo "Network connectivity OK."
        elif ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
            echo "Network connectivity OK (alternate DNS)."
        else
            echo "Network connectivity issue detected."
            echo "   Check: ip link, nmcli, or systemd-networkd"
        fi
        echo ""
        
        # 6. Check for critical error logs since boot
        echo "6. CHECKING CRITICAL ERROR LOGS"
        echo "------------------------------"
        if [[ $error_count -eq 0 ]]; then
            echo "No critical errors found."
        else
            echo "Critical errors since boot: $error_count (first 20 lines)"
            echo "$all_critical" | head -20
        fi
        echo ""
        
        # 7. Disk space check after updates
        echo "7. CHECKING DISK SPACE"
        echo "---------------------"
        local avail
        avail=$(df -BG / | awk 'NR==2 {print $4}' | tr -d G)
        echo "Available disk space: ${avail}GB"
        if [[ "$avail" -lt "$MIN_DISK_SPACE_WARN_GB" ]]; then
            echo "Low disk space after update - consider cleanup"
        fi
        echo ""
        
        # 8. Memory status
        echo "8. MEMORY STATUS"
        echo "---------------"
        while IFS= read -r line; do
            echo "   $line"
        done < <(free -h | grep -E "Mem|Swap")
        echo ""
        
        echo "=========================================="
        echo "Verification completed at $(date '+%F %T')"
        if [[ $verification_failed -eq 1 ]]; then
            echo "STATUS: ISSUES DETECTED"
        else
            echo "STATUS: HEALTHY"
        fi
        echo "=========================================="
        
    } > "$verification_log" 2>&1
    
    # Append verification log to main log file (full report)
    cat "$verification_log" >> "$LOGFILE"
    
    # Log summary to console and log (single line with timestamp)
    if [[ $verification_failed -eq 1 ]]; then
        log "Post-update verification found issues - see $verification_log"
        notify "Post-update issues detected - check verification log" critical
    else
        log "Post-update verification passed - see $verification_log"
    fi
    
    # Rotate old verification logs
    find "$VERIFICATION_LOG_DIR" -type f -name "verification_*.log" -mtime +"$MAX_VERIFICATION_AGE_DAYS" -delete 2>/dev/null || true
    
    return $verification_failed
}

# Track if reboot notification has been sent to avoid spam
REBOOT_NOTIFIED=false

# Quick verification for periodic checks (no new log file)
quick_verify() {
    local issues_found=0
    
    # Check for failed services
    if systemctl --failed --no-legend 2>/dev/null | grep -q "."; then
        log "Quick check: Failed services detected"
        notify "System degraded - check 'systemctl --failed'" critical
        issues_found=1
    fi
    
    # Check if reboot needed for kernel (only notify once)
    local installed_kernel
    local running_kernel
    installed_kernel=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-//')
    running_kernel=$(uname -r)
    if [[ "$installed_kernel" != "$running_kernel" ]]; then
        if [[ "$REBOOT_NOTIFIED" == "false" ]]; then
            log "Quick check: Reboot recommended - kernel updated to $installed_kernel"
            notify "Reboot recommended - kernel update requires reboot" normal
            REBOOT_NOTIFIED=true
        fi
    else
        # Reset notification flag if kernel matches (user rebooted)
        REBOOT_NOTIFIED=false
    fi
    
    return $issues_found
}

# ================= FETCH UPDATES =================
fetch_pending_updates() {
    local tmp
    tmp=$(mktemp) || { log "Failed to create temp file"; return 1; }
    
    # Clean up temp file on function exit
    trap 'rm -f "$tmp"' RETURN

    # DNF updates
    # Note: dnf check-update returns exit code 100 when updates are available
    # This is normal behavior, not an error
    sudo dnf makecache -q >> "$LOGFILE" 2>&1
    sudo dnf check-update > "$tmp" 2>/dev/null || true
    
    # Extract updates (|| true prevents grep failure from killing script)
    if grep -q -E '\.(x86_64|noarch|i686|aarch64)' "$tmp" 2>/dev/null; then
        grep -E '\.(x86_64|noarch|i686|aarch64)' "$tmp" \
            | awk '{print $1 " (" $2 ")"}' > "$STATE_DIR/dnf_list"
    else
        > "$STATE_DIR/dnf_list"
    fi

    # Flatpak updates
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

# ================= NOTIFICATIONS =================
notify_pending() {
    local msg=""
    local pkg_count=0
    local flatpak_count=0
    
    [[ -s "$STATE_DIR/dnf_list" ]] && pkg_count=$(wc -l < "$STATE_DIR/dnf_list")
    [[ -s "$STATE_DIR/flatpak_list" ]] && flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
    
    msg="Found updates: $pkg_count packages, $flatpak_count flatpaks"
    notify "$msg" normal
    
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
    local msg="Updates completed successfully"
    notify "$msg" normal
}

# ================= RUN UPDATES =================
# Global variables for exit codes (used for history logging)
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

    # Declare local variables with safe defaults (1 = failure)
    # DNF_EXIT defaults to 1; if tee fails under set -e, this safe default stands
    local DNF_EXIT=1 FLATPAK_EXIT=1
    local UPDATE_SUCCESS=1

    # Start keep-alive loop (global trap will clean it up)
    while true; do sudo -n true 2>/dev/null; sleep 60; done &
    KEEP_ALIVE_PID=$!

    # Run DNF updates with live logging
    log_raw "=============================="
    log_raw "Starting DNF/Package Updates"
    log_raw "=============================="
    
    # Note: exit code 124 means the command timed out
    # PIPESTATUS[0] must be read immediately after the pipe before any other command
    timeout "$TIMEOUT_SECONDS" sudo nobara-sync cli 2>&1 | tee -a "$LOGFILE"
    DNF_EXIT=${PIPESTATUS[0]}
    log_raw "DNF exit code: $DNF_EXIT"
    
    # Run Flatpak updates with live logging
    log_blank
    log_raw "=============================="
    log_raw "Starting Flatpak Updates"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo flatpak update -y 2>&1 | tee -a "$LOGFILE"
    FLATPAK_EXIT=${PIPESTATUS[0]}
    log_raw "Flatpak exit code: $FLATPAK_EXIT"
    
    # User flatpak updates (if system updates succeeded)
    if [[ $FLATPAK_EXIT -eq 0 ]]; then
        timeout "$TIMEOUT_SECONDS" flatpak update --user -y 2>&1 | tee -a "$LOGFILE"
        FLATPAK_EXIT=${PIPESTATUS[0]}
        log_raw "User Flatpak exit code: $FLATPAK_EXIT"
    fi

    # Store exit codes for history logging
    LAST_DNF_EXIT="$DNF_EXIT"
    LAST_FLATPAK_EXIT="$FLATPAK_EXIT"

    # Evaluate results
    log_blank
    log_raw "=============================="
    log_raw "Update Summary"
    log_raw "=============================="
    
    if [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -eq 0 ]]; then
        UPDATE_SUCCESS=0
        log_raw "Updates completed successfully"
        
        log "Running post-update cleanup..."
        # Cleanup commands - send output to both log and console
        sudo dnf autoremove -y 2>&1 | tee -a "$LOGFILE"
        sudo dnf clean packages 2>&1 | tee -a "$LOGFILE"
        sudo flatpak uninstall --unused -y 2>&1 | tee -a "$LOGFILE"
        flatpak uninstall --user --unused -y 2>&1 | tee -a "$LOGFILE"
        
        # Run post-update verification
        # Note: verification failure is informational only - does not affect update success
        log_blank
        log_raw "=============================="
        log_raw "Post-Update Verification"
        log_raw "=============================="
        
        # || true prevents verification failure from triggering set -e
        verify_system_health || true
    else
        log_raw "Updates failed (DNF: $DNF_EXIT, Flatpak: $FLATPAK_EXIT)"
    fi

    # Clean up keep-alive (global trap will also run, but this ensures immediate cleanup)
    cleanup_keepalive

    return "$UPDATE_SUCCESS"
}

# ================= ROTATE LOGS =================
rotate_logs() {
    find "$LOG_DIR" -type f \( -name "*.txt" -o -name "*.csv" \) -mtime +"$MAX_LOG_AGE_DAYS" -delete 2>/dev/null
}

# ================= MAIN LOOP =================
main() {
    # Parse command line arguments BEFORE logging startup (so mode is reflected)
    for arg in "$@"; do
        if [[ "$arg" == "--dry-run" ]]; then
            DRY_RUN=true
            break
        fi
    done
    
    # Log startup with the correct mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Auto-update service starting (PID $$) - DRY RUN MODE"
    else
        log "Auto-update service starting (PID $$)"
    fi

    # Backoff variables (declared once, outside the loop)
    local retry_delay=60
    local max_delay=3600

    while true; do
        # Check disk - backoff accumulates on repeated failures
        if ! check_disk; then 
            log "Disk check failed, retrying in ${retry_delay}s"
            sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi
        
        # Check battery - backoff accumulates on repeated failures
        # Note: retry_delay persists from disk failures, causing continued backoff
        if ! check_battery; then 
            log "Battery check failed, retrying in ${retry_delay}s"
            sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi

        # Both checks passed - reset backoff
        retry_delay=60

        fetch_pending_updates

        if updates_available; then
            notify_pending
            if run_updates; then
                notify_complete
                echo "$(date '+%F'),OK,DNF:${LAST_DNF_EXIT},FLATPAK:${LAST_FLATPAK_EXIT}" >> "$HISTORY_LOG"
                log "Update successful"
            else
                alert_failure "Update failed"
                echo "$(date '+%F'),FAIL,DNF:${LAST_DNF_EXIT:-unknown},FLATPAK:${LAST_FLATPAK_EXIT:-unknown}" >> "$HISTORY_LOG"
            fi
        else
            log "System is up to date."
            quick_verify
        fi

        rotate_logs
        sleep 1h
    done
}

# Run main function with command line arguments
main "$@"
