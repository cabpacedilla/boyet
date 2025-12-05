#!/usr/bin/env bash

# fedora-proactive-sec.sh
# Proactive Fedora/Nobara Security Monitor with Real-time Alerts and False Positive Filtering

LOCK_FILE="/tmp/security_check_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

mkdir -p "$HOME/scriptlogs"
LOGFILE="$HOME/scriptlogs/fedora-sec-proactive.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== Utility Functions =====
notify() {
  notify-send "🛡️ Fedora Proactive Security" "$1" &
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

# ===== Enable and Configure auditd =====
enable_auditd() {
  sudo systemctl enable --now auditd
  log_info "auditd service enabled."

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

# ===== Known harmless patterns to ignore =====
false_positive_patterns=(
  "Call to Suspend failed"
  "gnome-shell.*no suitable screen"
  "pulseaudio.*Connection refused"
  "systemd-logind.*failed to idle"
  "org.freedesktop.DBus.Error"
)

is_false_positive() {
  local line="$1"
  for pattern in "${false_positive_patterns[@]}"; do
    if echo "$line" | grep -qiE "$pattern"; then
      return 0  # true → it's a false positive
    fi
  done
  return 1  # false → it's a real alert
}

# ===== Real-time Log Monitoring =====
monitor_logs_proactively() {
  log_info "Monitoring logs in real-time for threats..."

  journalctl -f -p err..emerg -u fail2ban -u firewalld |
  while read -r line; do
    if echo "$line" | grep -E -i \
      "segfault|unauthorized|denied|failed|attack|exploit|rootkit|brute|ban|unban|blocked|drop|reject|port|zone|rule"; then
      if ! is_false_positive "$line"; then
        log_warn "Real-time log alert: $line"
      fi
    fi
  done
}

# ===== Critical Services Check =====
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

# ===== Real-time Auditd Alerts =====
real_time_audit_alerts() {
  log_info "Watching audit logs in real-time..."

  ausearch -i --input-logs --checkpoint="/tmp/audit_checkpoint" | while read -r line; do
    if echo "$line" | grep -E "passwd_changes|shadow_changes|su_exec|exec_watched|sudoers_changes"; then
      log_warn "AUDIT ALERT: $line"
    fi
  done
}

# ===== Main =====
startup_notify

echo -e "\n===== ENABLE AUDITD ===== $(date) =====" | tee -a "$LOGFILE"
enable_auditd

echo -e "\n===== CRITICAL SERVICES CHECK ===== $(date) =====" | tee -a "$LOGFILE"
monitor_system_services &

echo -e "\n===== REAL-TIME LOG MONITORING ===== $(date) =====" | tee -a "$LOGFILE"
monitor_logs_proactively &

echo -e "\n===== REAL-TIME AUDITD ALERTS ===== $(date) =====" | tee -a "$LOGFILE"
real_time_audit_alerts
