#!/usr/bin/env bash

# fedora-proactive-sec.sh
# Version 1.3 - Added Gmail Alerts via msmtp

LOCK_FILE="/tmp/security_check_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    echo "Script is already running."
    exit 1
fi

echo $$ > "$LOCK_FILE"

cleanup() {
    log_info "Shutting down security monitor..."
    pkill -P $$ 
    [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]] && rm -f "$LOCK_FILE"
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

mkdir -p "$HOME/scriptlogs"
LOGFILE="$HOME/scriptlogs/fedora-sec-proactive.log"
# Your target email
ALERT_EMAIL="capacedilla@gmail.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== Utility Functions =====
notify() { notify-send "🛡️ Security Alert" "$1" & }

send_email() {
    # This sends the alert to your Gmail
    echo -e "Subject: 🛡️ Security Alert from $(hostname)\n\nEvent: $1\nTime: $(date)\nHost: $(hostname)" | msmtp "$ALERT_EMAIL"
}

log_info() { echo -e "${YELLOW}[INFO]${NC} $1" | tee -a "$LOGFILE"; }
log_success() { echo -e "${GREEN}[ OK ]${NC} $1" | tee -a "$LOGFILE"; }

log_warn() { 
    echo -e "${RED}[WARN]${NC} $1" | tee -a "$LOGFILE"
    notify "$1"
    # Send email in the background so the script doesn't lag
    send_email "$1" & 
}

# ===== Enable and Configure auditd =====
enable_auditd() {
    if ! systemctl is-active --quiet auditd; then
        sudo systemctl enable --now auditd
    fi
    AUDIT_RULES="/etc/audit/rules.d/proactive.rules"
    if [ ! -f "$AUDIT_RULES" ]; then
        sudo tee "$AUDIT_RULES" > /dev/null <<EOF
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /bin/su -p x -k su_exec
EOF
        sudo augenrules --load
    fi
}

# ===== New: USB Monitoring =====
monitor_usb() {
    log_info "Starting USB monitor..."
    udevadm monitor --subsystem-match=usb --property | while read -r line; do
        if echo "$line" | grep -q "ID_MODEL="; then
            device=$(echo "$line" | cut -d'=' -f2)
            log_warn "USB Device Detected: $device"
        fi
    done
}

# ===== New: Login Failure Monitoring =====
monitor_logins() {
    log_info "Starting Login monitor..."
    journalctl -f -t login -t gdm-password -t sshd | while read -r line; do
        if echo "$line" | grep -qiE "fail|unauthenticated|invalid user"; then
            log_warn "LOGIN FAILURE: Suspicious access attempt detected!"
        fi
    done
}

# ===== Existing Engines =====
monitor_logs_proactively() {
    log_info "Starting Journal monitoring..."
    journalctl -f -p err..emerg | while read -r line; do
        if echo "$line" | grep -qiE "unauthorized|denied|attack|exploit|rootkit|brute"; then
            log_warn "Threat Detected: $(echo "$line" | cut -c1-60)"
        fi
    done
}

real_time_audit_alerts() {
    log_info "Starting Auditd stream..."
    sudo tail -n0 -f /var/log/audit/audit.log | while read -r line; do
        if echo "$line" | grep -E "passwd_changes|shadow_changes|su_exec|sudoers_changes"; then
            event_type=$(echo "$line" | grep -oP "key=\"\K[^\"]+")
            log_warn "CRITICAL: Sensitive file access! ($event_type)"
        fi
    done
}

monitor_services_loop() {
    while true; do
        for service in auditd firewalld; do
            if ! systemctl is-active --quiet "$service"; then
                log_warn "SERVICE DOWN: $service"
            fi
        done
        sleep 60
    done
}

# ===== Main =====
clear
echo "-------------------------------------------"
echo "    Enhanced Fedora Security Monitor V1.3    "
echo "-------------------------------------------"

enable_auditd

monitor_logs_proactively &
real_time_audit_alerts &
monitor_services_loop &
monitor_usb &
monitor_logins &

log_success "All security engines active."
wait
