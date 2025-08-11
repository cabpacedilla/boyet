#!/bin/bash
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & fail)
# Works on Fedora/Nobara with systemd journal
# Logs to ~/scriptlogs/login-monitor.log and sends desktop notifications

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Export DISPLAY and XDG_RUNTIME_DIR so notify-send works in GUI
export DISPLAY=:0
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

declare -A seen

echo "[$(date '+%F %T')] Starting login monitor..." | tee -a "$LOGFILE"
notify-send "Login Monitor" "Starting login monitor..."

journalctl -f -n0 -o short-iso --since now \
  _COMM=sshd _COMM=login _COMM=su _COMM=sudo | \
while read -r DATE TIME HOST PROC REST; do
    EVENT_ID="${DATE}_${TIME}_${PROC}_${REST}"
    [[ -n "${seen[$EVENT_ID]}" ]] && continue
    seen[$EVENT_ID]=1

    LINE="$DATE $TIME $PROC $REST"

    # SSH login success
    if [[ "$LINE" =~ Accepted\ password ]] || [[ "$LINE" =~ Accepted\ publickey ]]; then
        echo -e "${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "SSH Login" "✅ $LINE" -u normal
    fi

    # SSH login failure
    if [[ "$LINE" =~ Failed\ password ]]; then
        echo -e "${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "SSH Login" "❌ $LINE" -u critical
    fi

    # sudo session opened (success)
    if [[ "$LINE" =~ pam_unix\(sudo:session\):\ session\ opened ]]; then
        echo -e "${GREEN}[SUDO SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "Sudo Login" "✅ $LINE" -u normal
    fi

    # sudo authentication failure
    if [[ "$LINE" =~ pam_unix\(sudo:auth\):\ authentication\ failure ]]; then
        echo -e "${RED}[SUDO FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "Sudo Failure" "❌ $LINE" -u critical
    fi

    # (Optional) su command attempts can be added similarly if needed
done
