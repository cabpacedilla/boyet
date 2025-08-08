#!/bin/bash

# fedora-proactive-sec.sh
# Proactive Fedora/Nobara Security Monitor with Real-time Alerts

mkdir -p "$HOME/scriptlogs"
LOGFILE="$HOME/scriptlogs/fedora-sec-proactive.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

notify() {
  notify-send "🛡️ Fedora Proactive Security" "$1"
}

log_info() {
  echo -e "${YELLOW}[INFO]${NC} $1" | tee -a "$LOGFILE"
}

log_success() {
  echo -e "${GREEN}[ OK ]${NC} $1" | tee -a "$LOGFILE"
}

log_warn() {
  echo -e "${RED}[WARN]${NC} $1" | tee -a "$LOGFILE"
  notify "$1"
}

startup_notify() {
  notify "🛡️ Proactive Security Monitor started"
  log_info "Security monitor started at $(date)"
}

# Enable auditd and add proactive audit rules
enable_auditd() {
  sudo systemctl enable --now auditd
  log_info "auditd service enabled."

  # Add proactive rules if not yet present
  AUDIT_RULES="/etc/audit/rules.d/proactive.rules"
  if [ ! -f "$AUDIT_RULES" ]; then
    sudo tee "$AUDIT_RULES" > /dev/null <<EOF
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k ssh_config_changes
-w /bin/su -p x -k su_exec
-a exit,always -F arch=b64 -S execve -k exec_watched
EOF
    sudo augenrules --load
    log_success "auditd proactive rules applied."
  else
    log_info "auditd proactive rules already present."
  fi
}

monitor_logs_proactively() {
  log_info "Monitoring logs in real-time for threats..."

  journalctl -f -p err..emerg | while read -r line; do
    if echo "$line" | grep -E -i "segfault|unauthorized|denied|failed|attack|exploit|rootkit|brute"; then
      log_warn "Real-time log alert: $line"
    fi
  done
}

monitor_system_services() {
  critical_services=(auditd fail2ban firewalld)
  for service in "${critical_services[@]}"; do
    if ! systemctl is-active --quiet "$service"; then
      log_warn "CRITICAL: $service is not running!"
    else
      log_success "$service is running."
    fi
  done
}

real_time_audit_alerts() {
  log_info "Watching audit logs in real-time..."

  ausearch -i --input-logs --checkpoint="/tmp/audit_checkpoint" | while read -r line; do
    if echo "$line" | grep -E "passwd_changes|shadow_changes|su_exec|exec_watched|sudoers_changes"; then
      log_warn "AUDIT ALERT: $line"
    fi
  done
}

# Main proactive loop
startup_notify
enable_auditd
monitor_system_services &
monitor_logs_proactively &
real_time_audit_alerts
