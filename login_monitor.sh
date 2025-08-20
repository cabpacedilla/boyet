#!/bin/bash
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & failure)
# Handles multiple failures properly (no missed sudo/ssh attempts)
# Logs to ~/scriptlogs/login-monitor.log and sends desktop notifications

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Export so notify-send works in GUI
export DISPLAY=:0
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Cooldown seconds for identical repeated messages
COOLDOWN=5
declare -A last_event

# Function to send notifications and log them
send_alert() {
    TITLE="$1"
    MSG="$2"
    URGENCY="$3"
    notify-send "$TITLE" "$MSG" -u "$URGENCY"
    echo "[$(date '+%F %T')] [$TITLE] $MSG" >> "$LOGFILE"
}

echo "[$(date '+%F %T')] Starting login monitor..." | tee -a "$LOGFILE"
notify-send "🛡️ Login Monitor" "Starting login monitor..."

journalctl -f -n0 -o short-iso --since now \
  _COMM=sshd _COMM=sshd-session _COMM=sudo _COMM=su | \
while read -r LINE; do
    NOW=$(date +%s)
    TS=$(date '+%F %T')

    # Generate unique ID for each line (timestamp + comm + first few tokens)
    EVENT_ID=$(echo "$LINE" | awk '{print $1"_"$2"_"$4"_"$5}')
    if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
        continue
    fi
    last_event[$EVENT_ID]=$NOW

    # --- SSH ---
    if [[ "$LINE" =~ "sshd" || "$LINE" =~ "sshd-session" ]]; then
        if [[ "$LINE" =~ "Accepted " ]]; then
            USER=$(echo "$LINE" | awk '{print $9}')
            MSG="User: $USER | Time: $TS"
            echo -e "${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
            send_alert "✅ SSH Login Success" "$MSG" critical
        elif [[ "$LINE" =~ "Failed password" ]]; then
            USER=$(echo "$LINE" | awk '{print $9}')
            MSG="User: $USER | Time: $TS"
            echo -e "${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
            send_alert "❌ SSH Login Failed" "$MSG" critical
        elif [[ "$LINE" =~ "authentication failure" ]]; then
            USER=$(echo "$LINE" | grep -oP "user=\K[^ ]+")
            MSG="User: $USER | Time: $TS"
            echo -e "${RED}[SSH AUTH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
            send_alert "❌ SSH Authentication Failure" "$MSG" critical
        fi
    fi


    # --- SUDO ---
    if [[ "$LINE" =~ "sudo" && "$LINE" =~ "session opened" ]]; then
        USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")
        RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)
        CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
        CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
        MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"
        echo -e "${GREEN}[SUDO SUCCESS]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"
        send_alert "✅ Sudo Success" "$MSG" critical
    elif [[ "$LINE" =~ "sudo" && "$LINE" =~ "authentication failure" ]]; then
        USER=$(echo "$LINE" | grep -oP "user=\K[^ ]+")
        RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)
        CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
        CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
        MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"
        echo -e "${RED}[SUDO FAILURE]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"
        send_alert "❌ Sudo Failure" "$MSG" critical
    fi

    # --- SU ---
    if [[ "$LINE" =~ " su[" && "$LINE" =~ "session opened" ]]; then
        USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")
        MSG="User: $USER | Time: $TS"
        echo -e "${GREEN}[SU SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "✅ su Login Success" "$MSG" critical
    elif [[ "$LINE" =~ " su[" && "$LINE" =~ "authentication failure" ]]; then
        USER=$(echo "$LINE" | grep -oP "user=\K[^ ]+")
        MSG="User: $USER | Time: $TS"
        echo -e "${RED}[SU FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "❌ su Failure" "$MSG" critical
    fi
done
