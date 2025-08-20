#!/bin/bash
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & failure)
# Handles multiple failures properly (no missed sudo/ssh attempts)
# Logs both raw journal lines and clean messages to ~/scriptlogs/login-monitor.log
# Sends desktop notifications with user-friendly format

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

# Colors for terminal log
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
notify-send "🔒 Login Monitor" "Started login monitoring..."

journalctl -f -n0 -o short-iso --since now \
  _COMM=sshd _COMM=sudo _COMM=su | \
while read -r LINE; do
    NOW=$(date +%s)
    EVENT_ID=$(echo "$LINE" | awk '{print $1"_"$2"_"$4"_"$5}')

    if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
        continue
    fi
    last_event[$EVENT_ID]=$NOW

    # Extract common fields
    TS=$(echo "$LINE" | awk '{print $1" "$2}')   # timestamp
    HOST=$(hostname)

    # Function to send notify + log nicely
    send_alert() {
        local TITLE="$1"
        local MSG="$2"
        local URGENCY="$3"

        # Send notification
        notify-send "$TITLE" "$MSG" -u "$URGENCY"

        # Log clean entry
        echo "[$TS] [$TITLE] $MSG" >> "$LOGFILE"
    }

    # --- SSH ---
    if [[ "$LINE" =~ "sshd" && "$LINE" =~ "Accepted " ]]; then
        USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
        MSG="User: $USER@$HOST | Time: $TS"
        echo -e "${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "✅ SSH Login Success" "$MSG" critical

    elif [[ "$LINE" =~ "sshd" && "$LINE" =~ "Failed password" ]]; then
        USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
        IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")
        MSG="User: $USER | From: $IP | Time: $TS"
        echo -e "${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "❌ SSH Login Failure" "$MSG" critical
    fi

    # --- SUDO ---
    if [[ "$LINE" =~ "sudo" && "$LINE" =~ "session opened" ]]; then
        USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")
        CMD=$(journalctl _COMM=sudo -n1 -o cat | grep -oP "COMMAND=.+")
        MSG="User: $USER | Time: $TS | $CMD"
        echo -e "${GREEN}[SUDO SUCCESS]${NC} $LINE | $CMD" | tee -a "$LOGFILE"
        send_alert "✅ Sudo Command Run" "$MSG" critical

    elif [[ "$LINE" =~ "sudo" && "$LINE" =~ "authentication failure" ]]; then
        USER=$(echo "$LINE" | grep -oP "user=\K[^ ]+")
        CMD=$(journalctl _COMM=sudo -n1 -o cat | grep -oP "COMMAND=.+")
        MSG="User: $USER | Time: $TS | $CMD"
        echo -e "${RED}[SUDO FAILURE]${NC} $LINE | $CMD" | tee -a "$LOGFILE"
        send_alert "❌ Sudo Failure" "$MSG" critical

    elif [[ "$LINE" =~ "sudo" && "$LINE" =~ "incorrect password attempts" ]]; then
        USER=$(echo "$LINE" | grep -oP "user=\K[^ ]+")
        CMD=$(journalctl _COMM=sudo -n1 -o cat | grep -oP "COMMAND=.+")
        MSG="User: $USER | Time: $TS | $CMD"
        echo -e "${RED}[SUDO MULTIPLE FAILURES]${NC} $LINE | $CMD" | tee -a "$LOGFILE"
        send_alert "❌ Multiple Sudo Failures" "$MSG" critical
    fi

    # --- SU ---
    if [[ "$LINE" =~ " su[" && "$LINE" =~ "session opened" ]]; then
        FROM=$(echo "$LINE" | grep -oP "by \K[^ ]+")
        MSG="By User: $FROM | Time: $TS"
        echo -e "${GREEN}[SU SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "✅ su Session Opened" "$MSG" critical

    elif [[ "$LINE" =~ " su[" && "$LINE" =~ "authentication failure" ]]; then
        FROM=$(echo "$LINE" | grep -oP "user=\K[^ ]+")
        MSG="User: $FROM | Time: $TS"
        echo -e "${RED}[SU FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "❌ su Failure" "$MSG" critical
    fi
done
