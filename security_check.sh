#!/usr/bin/env bash
# ============================================================
# Fedora / Nobara Proactive Security Monitor
# Version 2.5
#
# Purpose:
#   Long-running workstation security monitoring using:
#
#     - auditd health and audit-rule validation
#     - audit.log real-time monitoring
#     - system journal security-event monitoring
#     - login/authentication monitoring
#     - USB device monitoring
#     - firewalld health monitoring
#     - security-service health monitoring
#     - desktop notifications
#     - optional msmtp email alerts
#
# IMPORTANT:
#   - AIDE is intentionally NOT integrated.
#   - The script does NOT automatically modify firewall rules.
#   - The script does NOT automatically restart failed services.
#   - The script does NOT automatically modify audit rules.
#   - The script does NOT automatically update an AIDE baseline.
#   - The script runs as a normal user.
#   - Some privileged monitors require passwordless sudo -n access.
#   - Missing sudo privileges cause privileged monitors to run
#     in degraded mode.
#
# Debug logging:
#   Set DEBUG_MONITORS=1 to log lifecycle events for all monitors.
#   Set DEBUG_AUDIT=1 to log audit monitor events (legacy).
#
# ============================================================

set -o nounset
set -o pipefail

export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

readonly SCRIPT_NAME="security_check"
readonly SCRIPT_VERSION="2.5"

readonly LOG_DIR="$HOME/scriptlogs"
readonly LOGFILE="$LOG_DIR/fedora-sec-proactive.log"

readonly ALERT_EMAIL="cabpacedilla@gmail.com"

readonly SERVICE_CHECK_INTERVAL=60
readonly SUPERVISOR_INTERVAL=15

readonly MAX_ALERT_LENGTH=300
readonly EMAIL_COOLDOWN_SECS=30

# ============================================================
# Runtime state
# ============================================================

if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]]; then
    RUNTIME_DIR="$XDG_RUNTIME_DIR"
else
    RUNTIME_DIR="$HOME/.cache"
    mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
    chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
fi

readonly RUNTIME_DIR

readonly LOCK_FILE="$RUNTIME_DIR/${SCRIPT_NAME}.lock"
readonly EMAIL_STATE_FILE="$RUNTIME_DIR/${SCRIPT_NAME}.last-email"
readonly EMAIL_LOCK_FILE="$RUNTIME_DIR/${SCRIPT_NAME}.email.lock"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

CHILD_PIDS=()
CLEANUP_RUNNING=0
SHUTDOWN_REQUESTED=0

# ============================================================
# Utility functions
# ============================================================

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

sanitize_alert() {
    local text="$1"

    text="${text//$'\n'/ }"
    text="${text//$'\r'/ }"

    if (( ${#text} > MAX_ALERT_LENGTH )); then
        text="${text:0:MAX_ALERT_LENGTH}..."
    fi

    printf '%s' "$text"
}

# Debug logger — gated by DEBUG_MONITORS=1
debug_log() {
    [[ "${DEBUG_MONITORS:-0}" == "1" ]] || return 0
    printf '[%s] [DEBUG] %s\n' "$(timestamp)" "$1" >> "$LOGFILE"
}

log_info() {
    local message="$1"
    printf '%b[%s] [INFO]%b %s\n' \
        "$YELLOW" "$(timestamp)" "$NC" "$message" |
        tee -a "$LOGFILE"
}

log_success() {
    local message="$1"
    printf '%b[%s] [ OK ]%b %s\n' \
        "$GREEN" "$(timestamp)" "$NC" "$message" |
        tee -a "$LOGFILE"
}

log_error() {
    local message="$1"
    printf '%b[%s] [ERROR]%b %s\n' \
        "$RED" "$(timestamp)" "$NC" "$message" |
        tee -a "$LOGFILE"
}

# ============================================================
# Orphan cleanup — runs BEFORE the lock is taken
# ============================================================

cleanup_orphans() {
    if [[ -f "$LOCK_FILE" ]]; then
        if flock -n "$LOCK_FILE" true 2>/dev/null; then
            :
        else
            printf '[%s] [INFO] Another instance holds the lock; skipping orphan cleanup.\n' \
                "$(timestamp)" >> "$LOGFILE" 2>/dev/null || true
            return 0
        fi
    fi

    local patterns=(
        "tail -n0 -F /var/log/audit/audit.log"
        "journalctl --follow --no-pager -p err..emerg"
        "journalctl --follow --no-pager -t sshd"
        "udevadm monitor --subsystem-match=usb"
    )

    local pattern
    local killed=0
    local pids

    for pattern in "${patterns[@]}"; do
        pids="$(pgrep -f "$pattern" 2>/dev/null | grep -v "^$$\$" || true)"

        if [[ -n "$pids" ]]; then
            printf '[%s] [INFO] Orphan cleanup: killing PIDs %s matching "%s"\n' \
                "$(timestamp)" "$(echo "$pids" | tr '\n' ' ')" "$pattern" >> "$LOGFILE"
            # shellcheck disable=SC2086
            kill -TERM $pids 2>/dev/null || true
            killed=$((killed + 1))
        fi
    done

    if (( killed > 0 )); then
        sleep 2

        for pattern in "${patterns[@]}"; do
            pids="$(pgrep -f "$pattern" 2>/dev/null | grep -v "^$$\$" || true)"
            if [[ -n "$pids" ]]; then
                # shellcheck disable=SC2086
                kill -KILL $pids 2>/dev/null || true
            fi
        done

        printf '[%s] [INFO] Orphan cleanup completed.\n' \
            "$(timestamp)" >> "$LOGFILE"
    fi
}

# ============================================================
# Logging initialization
# ============================================================

mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

touch "$LOGFILE"
chmod 600 "$LOGFILE"

# ============================================================
# Desktop notification
# ============================================================

notify() {
    local message="$1"

    if ! command -v notify-send >/dev/null 2>&1; then
        return 0
    fi

    notify-send \
        --app-name="Security Monitor" \
        "Security Alert" \
        "$message" \
        >/dev/null 2>&1 &
}

# ============================================================
# Shared email rate limiter
# ============================================================

email_allowed() {
    local now
    local last=0
    local fd

    now="$(date +%s)"

    exec {fd}>"$EMAIL_LOCK_FILE"

    if ! flock -n "$fd"; then
        exec {fd}>&-
        return 1
    fi

    if [[ -f "$EMAIL_STATE_FILE" ]]; then
        read -r last < "$EMAIL_STATE_FILE" || last=0
    fi

    if [[ ! "$last" =~ ^[0-9]+$ ]]; then
        last=0
    fi

    if (( now - last < EMAIL_COOLDOWN_SECS )); then
        flock -u "$fd" || true
        exec {fd}>&-
        return 1
    fi

    printf '%s\n' "$now" > "$EMAIL_STATE_FILE"

    flock -u "$fd" || true
    exec {fd}>&-

    return 0
}

send_email() {
    local message="$1"
    local subject
    local body

    if ! command -v msmtp >/dev/null 2>&1; then
        return 0
    fi

    if ! email_allowed; then
        return 0
    fi

    subject="Security Alert from $(hostname)"

    body=$(
        printf 'Event: %s\nTime: %s\nHost: %s\n' \
            "$message" "$(timestamp)" "$(hostname)"
    )

    if ! printf 'Subject: %s\n\n%s\n' "$subject" "$body" |
        msmtp "$ALERT_EMAIL" >/dev/null 2>&1; then
        printf '[%s] [WARN] Email alert delivery failed.\n' \
            "$(timestamp)" >> "$LOGFILE"
    fi
}

# ============================================================
# Central warning function
# ============================================================

log_warn() {
    local message
    message="$(sanitize_alert "$1")"

    printf '%b[%s] [WARN]%b %s\n' \
        "$RED" "$(timestamp)" "$NC" "$message" |
        tee -a "$LOGFILE"

    notify "$message"
    send_email "$message" &
}

# ============================================================
# Dependency checks
# ============================================================

check_dependencies() {
    local required_commands=(
        systemctl journalctl sudo flock udevadm firewall-cmd
    )
    local command

    for command in "${required_commands[@]}"; do
        if ! command -v "$command" >/dev/null 2>&1; then
            log_error "Required command not found: $command"
            return 1
        fi
    done

    if [[ ! -x /usr/bin/tail ]]; then
        log_error "Required binary not found: /usr/bin/tail"
        return 1
    fi

    if command -v notify-send >/dev/null 2>&1; then
        log_info "Desktop notification support: available"
    else
        log_info "Desktop notification support: unavailable"
    fi

    if command -v msmtp >/dev/null 2>&1; then
        log_info "Email alert support: available"
    else
        log_info "Email alert support: unavailable"
    fi

    return 0
}

# ============================================================
# Non-interactive sudo validation
# ============================================================

check_sudo_noninteractive() {
    if sudo -n true >/dev/null 2>&1; then
        log_success "Non-interactive sudo access: available"
        return 0
    fi

    log_warn \
        "Non-interactive sudo access is unavailable; privileged monitors may be disabled."

    return 1
}

# ============================================================
# Auditd health
# ============================================================

check_auditd() {
    local status
    local lost

    if ! systemctl is-active --quiet auditd; then
        log_warn "SERVICE DOWN: auditd"
        return 1
    fi

    status="$(sudo -n /usr/sbin/auditctl -s 2>/dev/null)" || {
        log_warn \
            "CRITICAL: auditd is active but auditctl status could not be queried."
        return 1
    }

    if grep -q '^lost [1-9]' <<< "$status"; then
        lost="$(awk '/^lost / {print $2}' <<< "$status")"
        log_warn "CRITICAL: auditd has lost $lost events."
    fi

    return 0
}

# ============================================================
# Expected proactive audit rules
# ============================================================

validate_audit_rules() {
    local audit_rules="/etc/audit/rules.d/proactive.rules"
    local loaded_rules
    local missing=0
    local expected_rule

    if ! sudo -n test -f "$audit_rules"; then
        log_warn \
            "CRITICAL: Expected audit rule file is missing: $audit_rules"
        return 1
    fi

    loaded_rules="$(sudo -n /usr/sbin/auditctl -l 2>/dev/null)" || {
        log_warn "CRITICAL: Unable to retrieve loaded audit rules."
        return 1
    }

    while IFS= read -r expected_rule; do
        [[ -z "$expected_rule" ]] && continue
        [[ "$expected_rule" == \#* ]] && continue

        if ! sudo -n grep -Fqx -- "$expected_rule" "$audit_rules"; then
            log_warn \
                "AUDIT RULE DRIFT: Missing from $audit_rules: $expected_rule"
            missing=1
        fi
    done <<'EOF'
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /bin/su -p x -k su_exec
EOF

    if ! grep -Fq -- '-w /etc/passwd -p wa -k passwd_changes' <<< "$loaded_rules"; then
        log_warn "AUDIT RULE NOT LOADED: passwd_changes"
        missing=1
    fi

    if ! grep -Fq -- '-w /etc/shadow -p wa -k shadow_changes' <<< "$loaded_rules"; then
        log_warn "AUDIT RULE NOT LOADED: shadow_changes"
        missing=1
    fi

    if ! grep -Fq -- '-w /etc/sudoers -p wa -k sudoers_changes' <<< "$loaded_rules"; then
        log_warn "AUDIT RULE NOT LOADED: sudoers_changes"
        missing=1
    fi

    if ! grep -Fq -- '-w /bin/su -p x -k su_exec' <<< "$loaded_rules"; then
        log_warn "AUDIT RULE NOT LOADED: su_exec"
        missing=1
    fi

    if (( missing == 0 )); then
        log_success "Proactive audit rules validated."
        return 0
    fi

    return 1
}

# ============================================================
# Audit initialization
# ============================================================

initialize_audit() {
    log_info "Checking audit subsystem..."

    if ! check_auditd; then
        return 1
    fi

    if ! validate_audit_rules; then
        log_warn \
            "Audit configuration requires administrator review."
    fi

    return 0
}

# ============================================================
# Real-time audit log monitor (with retry loop)
# ============================================================

real_time_audit_alerts() {
    local line
    local event_type

    debug_log "audit: function entered (pid=$$)"

    log_info "Audit log monitor starting."

    if ! sudo -n true 2>/dev/null; then
        log_warn "AUDIT MONITOR UNAVAILABLE: no passwordless sudo."
        debug_log "audit: gate 1 FAILED — exiting"
        return 1
    fi

    if ! sudo -n test -r /var/log/audit/audit.log 2>/dev/null; then
        log_warn \
            "AUDIT MONITOR UNAVAILABLE: audit.log is not readable via sudo."
        debug_log "audit: gate 2 FAILED — exiting"
        return 1
    fi

    debug_log "audit: gates passed, entering retry loop"

    while (( SHUTDOWN_REQUESTED == 0 )); do
        debug_log "audit: entering tail pipeline"

        sudo -n /usr/bin/tail \
            -n0 -F /var/log/audit/audit.log 2>/dev/null |
        while IFS= read -r line; do
            if [[ "$line" =~ key=\"(passwd_changes|shadow_changes|su_exec|sudoers_changes)\" ]]; then
                event_type="${BASH_REMATCH[1]}"
                log_warn \
                    "CRITICAL: Sensitive audit event detected ($event_type)"
            fi
        done

        debug_log "audit: tail pipeline exited"

        if (( SHUTDOWN_REQUESTED == 0 )); then
            printf '[%s] [WARN] Audit tail exited; restarting in 5s\n' \
                "$(timestamp)" >> "$LOGFILE"
            sleep 5
        fi
    done

    debug_log "audit: retry loop exited"
}

# ============================================================
# Journal security monitor (with debug instrumentation)
# ============================================================

monitor_logs_proactively() {
    local line

    debug_log "journal: function entered (pid=$$)"

    log_info "Journal security monitor started."

    while (( SHUTDOWN_REQUESTED == 0 )); do
        debug_log "journal: entering journalctl pipeline"

        journalctl --follow --no-pager -p err..emerg 2>/dev/null |
        while IFS= read -r line; do
            debug_log "journal: received line"
            if [[ "$line" =~ unauthorized[[:space:]]access|permission[[:space:]]denied|access[[:space:]]denied|rootkit[[:space:]]detected|brute[[:space:]]force|brute-force|authentication[[:space:]]failure ]]; then
                line="$(sanitize_alert "$line")"
                log_warn "Threat Indicator: $line"
            fi
        done

        debug_log "journal: journalctl pipeline exited"

        if (( SHUTDOWN_REQUESTED == 0 )); then
            printf '[%s] [WARN] Journal monitor exited; restarting in 5s\n' \
                "$(timestamp)" >> "$LOGFILE"
            sleep 5
        fi
    done

    debug_log "journal: function returning"
}

# ============================================================
# Login/authentication monitor (with debug instrumentation)
# ============================================================

monitor_logins() {
    local line

    debug_log "login: function entered (pid=$$)"

    log_info "Login/authentication monitor started."

    while (( SHUTDOWN_REQUESTED == 0 )); do
        debug_log "login: entering journalctl pipeline"

        journalctl --follow --no-pager \
            -t sshd -t sudo -t polkitd -t systemd-logind -t sddm 2>/dev/null |
        while IFS= read -r line; do
            debug_log "login: received line"
            if [[ "$line" =~ failed[[:space:]]password|authentication[[:space:]]failure|invalid[[:space:]]user|FAILED[[:space:]]LOGIN ]]; then
                line="$(sanitize_alert "$line")"
                log_warn "LOGIN/AUTH FAILURE: $line"
            fi
        done

        debug_log "login: journalctl pipeline exited"

        if (( SHUTDOWN_REQUESTED == 0 )); then
            printf '[%s] [WARN] Login monitor exited; restarting in 5s\n' \
                "$(timestamp)" >> "$LOGFILE"
            sleep 5
        fi
    done

    debug_log "login: function returning"
}

# ============================================================
# USB monitor (with retry loop)
# ============================================================

monitor_usb() {
    local line
    local action=""
    local model=""
    local vendor=""

    debug_log "usb: function entered (pid=$$)"

    log_info "USB monitor started."

    while (( SHUTDOWN_REQUESTED == 0 )); do
        debug_log "usb: entering udevadm pipeline"

        udevadm monitor --subsystem-match=usb --property 2>/dev/null |
        while IFS= read -r line; do
            case "$line" in
                ACTION=*)
                    action="${line#ACTION=}"
                    ;;
                ID_MODEL=*)
                    model="${line#ID_MODEL=}"
                    ;;
                ID_VENDOR=*)
                    vendor="${line#ID_VENDOR=}"
                    ;;
                "")
                    if [[ "$action" == "add" ]]; then
                        if [[ -n "$vendor" && -n "$model" ]]; then
                            log_warn "USB Device Connected: ${vendor} ${model}"
                        elif [[ -n "$model" ]]; then
                            log_warn "USB Device Connected: ${model}"
                        else
                            log_warn "USB Device Connected: unidentified USB device"
                        fi
                    fi
                    action=""
                    model=""
                    vendor=""
                    ;;
            esac
        done

        debug_log "usb: udevadm pipeline exited"

        if (( SHUTDOWN_REQUESTED == 0 )); then
            printf '[%s] [WARN] USB monitor exited; restarting in 5s\n' \
                "$(timestamp)" >> "$LOGFILE"
            sleep 5
        fi
    done

    debug_log "usb: function returning"
}

# ============================================================
# Firewalld health
# ============================================================

check_firewalld() {
    local zones

    if ! systemctl is-active --quiet firewalld; then
        log_warn "SERVICE DOWN: firewalld"
        return 1
    fi

    if ! firewall-cmd --state 2>/dev/null | grep -qx 'running'; then
        log_warn \
            "CRITICAL: firewalld service is active but firewall state is not running."
        return 1
    fi

    zones="$(firewall-cmd --get-active-zones 2>/dev/null)" || {
        log_warn \
            "CRITICAL: Unable to query firewalld active zones."
        return 1
    }

    if [[ -z "${zones//[[:space:]]/}" ]]; then
        log_warn "CRITICAL: firewalld has no active zone."
        return 1
    fi

    return 0
}

# ============================================================
# Security service monitor
# ============================================================

monitor_services_loop() {
    local service

    debug_log "services: function entered (pid=$$)"

    log_info "Security service health monitor started."

    while (( SHUTDOWN_REQUESTED == 0 )); do
        for service in auditd firewalld; do
            if ! systemctl is-active --quiet "$service"; then
                log_warn "SERVICE DOWN: $service"
            fi
        done

        check_firewalld || true
        sleep "$SERVICE_CHECK_INTERVAL"
    done
}

# ============================================================
# Monitor process registration
# ============================================================

register_child() {
    local pid="$1"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        CHILD_PIDS+=("$pid")
    fi
}

# ============================================================
# Process liveness check
# ============================================================

is_child_alive() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

# ============================================================
# Cleanup
# ============================================================

cleanup() {
    local pid

    if (( CLEANUP_RUNNING != 0 )); then
        return 0
    fi

    CLEANUP_RUNNING=1
    SHUTDOWN_REQUESTED=1

    printf '\n'

    for pid in "${CHILD_PIDS[@]}"; do
        if is_child_alive "$pid"; then
            kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        fi
    done

    sleep 2

    for pid in "${CHILD_PIDS[@]}"; do
        if is_child_alive "$pid"; then
            kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        fi
    done

    log_info "Security monitor stopped."

    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

trap 'SHUTDOWN_REQUESTED=1; exit 130' INT
trap 'SHUTDOWN_REQUESTED=1; exit 143' TERM
trap 'SHUTDOWN_REQUESTED=1; exit 129' HUP
trap cleanup EXIT

# ============================================================
# Supervisor
# ============================================================

supervise_monitors() {
    local name
    local pid
    local index

    local names=(
        "journal"
        "audit"
        "login"
        "usb"
        "services"
    )

    debug_log "supervisor: function entered (pid=$$)"

    log_info "Security monitor supervisor started."

    while (( SHUTDOWN_REQUESTED == 0 )); do
        for index in "${!CHILD_PIDS[@]}"; do
            pid="${CHILD_PIDS[$index]}"
            name="${names[$index]:-monitor-$index}"

            if ! is_child_alive "$pid"; then
                log_warn \
                    "MONITOR STOPPED: $name monitor is no longer running."
                CHILD_PIDS[$index]="0"
            fi
        done

        sleep "$SUPERVISOR_INTERVAL"
    done
}

# ============================================================
# Main
# ============================================================

main() {
    if [[ -t 1 ]]; then
        clear
    fi

    echo "-------------------------------------------"
    echo " Fedora/Nobara Proactive Security Monitor"
    echo "              Version $SCRIPT_VERSION"
    echo "-------------------------------------------"
    echo

    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"

    cleanup_orphans

    exec 9>"$LOCK_FILE"

    if ! flock -n 9; then
        echo "Security monitor is already running."
        exit 1
    fi

    set -m

    if ! check_dependencies; then
        log_error "Dependency validation failed."
        return 1
    fi

    if ! check_sudo_noninteractive; then
        log_warn \
            "Continuing in degraded mode; privileged checks may be unavailable."
    fi

    initialize_audit || true

    if check_firewalld; then
        log_success "firewalld is active with an active zone."
    else
        log_warn "Initial firewalld health validation failed."
    fi

    monitor_logs_proactively </dev/null >/dev/null 2>&1 &
    register_child "$!"

    real_time_audit_alerts </dev/null >/dev/null 2>&1 &
    register_child "$!"

    monitor_logins </dev/null >/dev/null 2>&1 &
    register_child "$!"

    monitor_usb </dev/null >/dev/null 2>&1 &
    register_child "$!"

    monitor_services_loop </dev/null >/dev/null 2>&1 &
    register_child "$!"

    log_success "Security monitoring engines started."

    supervise_monitors </dev/null >/dev/null 2>&1 &
    register_child "$!"

    while (( SHUTDOWN_REQUESTED == 0 )); do
        sleep 5
    done
}

main "$@"
