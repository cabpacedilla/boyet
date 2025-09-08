#!/bin/bash

# login_monitor.sh
# Real-time login alerts for SSH, TTY, su, and sudo attempts (success & fail)
# Requires: notify-send (libnotify), journalctl (systemd)

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "[$(date '+%F %T')] Starting login monitor..." | tee -a "$LOGFILE"
notify-send "Login Monitor" "Starting login monitor..."

# Monitor relevant sources:
# -u sshd           → SSH login attempts
# -u systemd-logind → Local/TTY sessions
# -u login          → Console logins
# _COMM=su          → su command attempts
# _COMM=sudo        → sudo attempts
journalctl -f -u sshd -u systemd-logind -u login _COMM=su _COMM=sudo --since now | while read -r line; do
    DATE=$(date '+%F %T')

    # Successful login/session open
    if echo "$line" | grep -qE "Accepted password|Accepted publickey|session opened for user|sudo:.*TTY=.* ; PWD=.* ; USER=.* ; COMMAND=.*"; then
        echo -e "${GREEN}[SUCCESS]${NC} Successful login at $DATE" | tee -a "$LOGFILE"
        echo "$line" >> "$LOGFILE"
        notify-send "Login Alert" "✅ Successful login at $DATE" -u normal
    fi

    # Failed login/authentication
    if echo "$line" | grep -qE "Failed password|authentication failure|sudo: .*authentication failure"; then
        echo -e "${RED}[FAILURE]${NC} Failed login attempt at $DATE" | tee -a "$LOGFILE"
        echo "$line" >> "$LOGFILE"
        notify-send "Login Alert" "❌ Failed login attempt at $DATE" -u critical
    fi
done
