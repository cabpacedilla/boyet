#!/bin/bash

# security_audit.sh
# Runs a full security audit automatically at 2 AM every day
# Keeps running in the background without cron or systemd

mkdir -p "$HOME/scriptlogs"
LOGFILE="$HOME/scriptlogs/fedora-sec-audit.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

notify() {
  notify-send "🛡️ Fedora Security Check" "$1"
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
  notify "Fedora Security Check started. Waiting for 2 AM..."
  log_info "Security audit scheduler started at $(date)"
}

section_header() {
  echo -e "\n========= $1 ($(date '+%Y-%m-%d %H:%M:%S')) =========\n" >> "$LOGFILE"
}

chkrootkit_check() {
  section_header "CHKROOTKIT"
  log_info "Running chkrootkit..."
  output=$(sudo /usr/bin/chkrootkit)
  echo "$output" >> "$LOGFILE"
  if echo "$output" | grep -q 'INFECTED'; then
    log_warn "chkrootkit found infection!"
  else
    log_success "chkrootkit reports clean."
  fi
}

aide_check() {
  section_header "AIDE"
  log_info "Running AIDE integrity check..."
  output=$(sudo /usr/bin/aide --check)
  echo "$output" >> "$LOGFILE"
  if echo "$output" | grep -q 'found differences'; then
    log_warn "AIDE detected file changes!"
  else
    log_success "AIDE reports no changes."
  fi
}

analyze_logs() {
  section_header "CRITICAL LOGS"
  log_info "Checking logs for critical alerts..."
  output=$(sudo journalctl -p err..alert --since "2 days ago")
  echo "$output" >> "$LOGFILE"
  if [ -n "$output" ]; then
    log_warn "Critical log entries found!"
  else
    log_success "No recent critical logs."
  fi
}

network_check() {
  section_header "NETWORK"
  log_info "Checking open ports and connections..."
  sudo /usr/bin/ss -tulnp >> "$LOGFILE"
  sudo lsof -i >> "$LOGFILE"
  log_success "Network scan completed."
}

clamav_scan() {
  section_header "CLAMAV"
  log_info "Updating and scanning with ClamAV..."
  sudo freshclam >> "$LOGFILE" 2>&1
  output=$(sudo clamscan -r /)
  echo "$output" >> "$LOGFILE"
  if echo "$output" | grep -q 'Infected files: [^0]'; then
    log_warn "ClamAV found malware!"
  else
    log_success "ClamAV scan clean."
  fi
}

package_check() {
  section_header "PACKAGE INTEGRITY"
  log_info "Checking for unauthorized packages..."
  rpm -qa --last | head >> "$LOGFILE"
  rpm -Va >> "$LOGFILE"
  dnf repoquery --unavailable --installed >> "$LOGFILE"
  log_success "Package audit complete."
}

check_users() {
  section_header "USER ACCOUNTS"
  log_info "Checking user accounts..."
  cat /etc/passwd >> "$LOGFILE"
  log_success "User list saved."
}

check_sudo_usage() {
  section_header "SUDO USAGE"
  log_info "Checking sudo usage..."
  sudo grep sudo /var/log/secure >> "$LOGFILE"
  log_success "Sudo history logged."
}

check_user_history() {
  section_header "SHELL HISTORY"
  log_info "Backing up shell history files..."
  cp ~/.bash_history "$HOME/scriptlogs/bash_history_$USER" 2>/dev/null
  sudo cp /root/.bash_history "$HOME/scriptlogs/bash_history_root" 2>/dev/null
  log_success "History files backed up."
}

check_services() {
  section_header "ACTIVE SERVICES"
  log_info "Listing active systemd services..."
  systemctl list-units --type=service >> "$LOGFILE"
  log_success "Service list logged."
}

check_enabled_services() {
  section_header "ENABLED SERVICES AT BOOT"
  log_info "Listing enabled services at boot..."
  systemctl list-unit-files --state=enabled >> "$LOGFILE"
  log_success "Enabled services logged."
}

lynis_audit() {
  section_header "LYNIS"
  log_info "Running Lynis audit..."
  output=$(sudo lynis audit system)
  echo "$output" >> "$LOGFILE"
  log_success "Lynis audit complete."
}

security_updates() {
  section_header "SECURITY UPDATES"
  log_info "Checking for CVE security updates..."
  sudo dnf updateinfo list security all >> "$LOGFILE"
  log_success "Security update list complete."
}

check_auditd() {
  section_header "AUDITD STATUS"
  log_info "Checking auditd status..."
  if systemctl is-active --quiet auditd; then
    log_success "auditd is running."
  else
    log_warn "auditd is NOT running! Real-time syscall tracking disabled."
  fi
}

check_fail2ban() {
  section_header "FAIL2BAN STATUS"
  log_info "Checking fail2ban status..."
  if systemctl is-active --quiet fail2ban; then
    log_success "fail2ban is active (brute-force protection enabled)."
  else
    log_warn "fail2ban is NOT running! Brute-force attack prevention disabled."
  fi
}

check_psacct() {
  section_header "PSACCT/ACCT STATUS"
  log_info "Checking psacct/acct status..."
  if systemctl is-active --quiet psacct || systemctl is-active --quiet acct; then
    log_success "psacct/acct is running (user activity tracking enabled)."
  else
    log_warn "psacct/acct is NOT running! User command auditing disabled."
  fi
}

run_logwatch() {
  section_header "LOGWATCH SUMMARY"
  log_info "Running logwatch for summary..."
  output=$(sudo /usr/bin/logwatch --detail Low --range yesterday --service All --mailto root)
  echo "$output" >> "$LOGFILE"
  log_success "Logwatch summary generated."
}

run_all_checks() {
  startup_notify
  aide_check
  analyze_logs
  network_check
  clamav_scan
  package_check
  check_users
  check_sudo_usage
  check_user_history
  check_services
  check_enabled_services
  lynis_audit
  security_updates
  check_auditd
  check_fail2ban
  check_psacct
  run_logwatch
  log_info "All security checks completed."
  notify "Fedora Security Check completed."
}

# Scheduler loop for 2 AM run
startup_notify
while true; do
    current_time=$(date +%H:%M)
    if [[ "$current_time" == "02:00" ]]; then
        run_all_checks
        sleep 60  # avoid running multiple times in the same minute
    fi
    sleep 30
done
