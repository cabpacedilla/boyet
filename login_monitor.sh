#!/bin/bash
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & failure)
# Handles multiple failures properly (no missed sudo/ssh attempts)
# Logs to ~/scriptlogs/login-monitor.log and sends desktop notifications

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Export so notify-send works in GUI
export DISPLAY=:0
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Cooldown seconds for identical repeated messages
COOLDOWN=5
declare -A last_event

echo "[$(date '+%F %T')] Starting login monitor..." | tee -a "$LOGFILE"
notify-send "Login Monitor" "Starting login monitor..."

journalctl -f -n0 -o short-iso --since now \
  _COMM=sshd _COMM=sudo _COMM=su | \
while read -r LINE; do
    NOW=$(date +%s)

    # Generate unique ID for each line (timestamp + comm + first few tokens)
    EVENT_ID=$(echo "$LINE" | awk '{print $1"_"$2"_"$4"_"$5}')

    if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
        continue
    fi
    last_event[$EVENT_ID]=$NOW

    # --- SSH ---
    if [[ "$LINE" =~ "sshd" && "$LINE" =~ "Accepted " ]]; then
        echo -e "${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "SSH Login" "✅ $LINE" -u normal
    elif [[ "$LINE" =~ "sshd" && "$LINE" =~ "Failed password" ]]; then
        echo -e "${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "SSH Login" "❌ $LINE" -u critical
    fi

    # --- SUDO ---
    if [[ "$LINE" =~ "sudo" && "$LINE" =~ "session opened" ]]; then
        echo -e "${GREEN}[SUDO SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "Sudo Login" "✅ $LINE" -u normal
    elif [[ "$LINE" =~ "sudo" && "$LINE" =~ "authentication failure" ]]; then
        echo -e "${RED}[SUDO FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "Sudo Failure" "❌ $LINE" -u critical
    elif [[ "$LINE" =~ "sudo" && "$LINE" =~ "incorrect password attempts" ]]; then
        echo -e "${RED}[SUDO MULTIPLE FAILURES]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "Sudo Failure" "❌ $LINE" -u critical
    fi

    # --- SU ---
    if [[ "$LINE" =~ " su[" && "$LINE" =~ "session opened" ]]; then
        echo -e "${GREEN}[SU SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "su Login" "✅ $LINE" -u normal
    elif [[ "$LINE" =~ " su[" && "$LINE" =~ "authentication failure" ]]; then
        echo -e "${RED}[SU FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        notify-send "su Failure" "❌ $LINE" -u critical
    fi
done
