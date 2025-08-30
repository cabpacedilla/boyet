#!/bin/bash

# security_audit.sh
# Fedora/Nobara Security Audit Script
# Runs periodic system-wide security checks without overlapping with proactive monitor.
# Now includes section headers and timestamps in all log entries.

mkdir -p "$HOME/scriptlogs"
LOGFILE="$HOME/scriptlogs/fedora-sec-audit.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== Utility Functions =====
timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log_info() {
  echo -e "$(timestamp) ${YELLOW}[INFO]${NC} $1" | tee -a "$LOGFILE"
}

log_success() {
  echo -e "$(timestamp) ${GREEN}[ OK ]${NC} $1" | tee -a "$LOGFILE"
}

log_warn() {
  echo -e "$(timestamp) ${RED}[WARN]${NC} $1" | tee -a "$LOGFILE"
}

notify() {
  notify-send "🛡️ Fedora Security Audit" "$1"
}

# ===== Check File Permissions =====
check_permissions() {
  echo -e "\n===== FILE PERMISSIONS CHECK ===== $(date) =====" | tee -a "$LOGFILE"
  log_info "Checking sensitive file permissions..."
  declare -A files=(
    ["/etc/passwd"]="644"
    ["/etc/shadow"]="000"
    ["/etc/sudoers"]="440"
  )

  for file in "${!files[@]}"; do
    if [ -f "$file" ]; then
      perms=$(stat -c "%a" "$file")
      if [ "$perms" -eq "${files[$file]}" ]; then
        log_success "$file permissions are secure ($perms)."
      else
        log_warn "$file permissions are $perms (should be ${files[$file]})."
      fi
    fi
  done
}

# ===== Check Rootkits with chkrootkit =====
check_rootkits() {
  echo -e "\n===== ROOTKIT SCAN ===== $(date) =====" | tee -a "$LOGFILE"
  log_info "Running rootkit check with chkrootkit..."
  if command -v chkrootkit &>/dev/null; then
    sudo chkrootkit 2>&1 | tee -a "$LOGFILE"
    log_success "chkrootkit scan complete."
  else
    log_warn "chkrootkit not installed. Install with: sudo dnf install chkrootkit -y"
  fi
}

# ===== Malware Scan with ClamAV =====
clamav_scan() {
  echo -e "\n===== CLAMAV MALWARE SCAN ===== $(date) =====" | tee -a "$LOGFILE"
  log_info "Running ClamAV malware scan..."
  if command -v clamscan &>/dev/null; then
    sudo freshclam
    sudo clamscan -r --bell -i / 2>&1 | tee -a "$LOGFILE"
    log_success "ClamAV scan finished."
  else
    log_warn "ClamAV not installed. Install with: sudo dnf install clamav -y"
  fi
}

# ===== Main =====
echo -e "\n===== FEDORA SECURITY AUDIT STARTED ===== $(date) =====" | tee -a "$LOGFILE"
check_permissions
check_rootkits
clamav_scan
echo -e "\n===== FEDORA SECURITY AUDIT COMPLETED ===== $(date) =====" | tee -a "$LOGFILE"
notify "Security audit completed. Check $LOGFILE for details."
