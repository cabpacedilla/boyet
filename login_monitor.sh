#!/bin/bash
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & failure)
# Logs to ~/scriptlogs/login-monitor.log and sends desktop notifications
# Requires: libnotify (notify-send command)

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

    # --- SSH ---
    if [[ "$LINE" =~ "sshd" || "$LINE" =~ "sshd-session" ]]; then
        if [[ "$LINE" =~ "Accepted " ]]; then
            USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
            IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")
            # More specific Event ID for SSH success
            EVENT_ID="ssh_success_${USER}_${IP}_$(echo "$LINE" | awk '{print $1}')"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            MSG="User: $USER | From: $IP | Time: $TS"
            echo -e "${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
            send_alert "✅ SSH Login Success" "$MSG" critical

        elif [[ "$LINE" =~ "Failed password" ]]; then
            USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
            IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")
            # Unique Event ID for each SSH failure (include microseconds if available)
            EVENT_ID="ssh_fail_${USER}_${IP}_${NOW}_$(echo "$LINE" | awk '{print $1"_"$2}')"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            MSG="User: $USER | From: $IP | Time: $TS"
            echo -e "${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
            send_alert "❌ SSH Login Failed" "$MSG" critical
        fi
    fi

    # --- SUDO ---
    if [[ "$LINE" =~ "sudo" ]]; then
        if [[ "$LINE" =~ "session opened" ]]; then
            USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")
            # More specific Event ID for sudo success
            EVENT_ID="sudo_success_${USER}_$(echo "$LINE" | awk '{print $1"_"$2}')"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)
            CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
            CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
            MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"
            echo -e "${GREEN}[SUDO SUCCESS]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"
            send_alert "✅ Sudo Success" "$MSG" critical

        elif [[ "$LINE" =~ "authentication failure" ]] || [[ "$LINE" =~ "incorrect password" ]] || [[ "$LINE" =~ "sorry, try again" ]] || [[ "$LINE" =~ "password attempts" ]]; then
            # Try multiple patterns to extract username from sudo failure messages
            if [[ "$LINE" =~ "user="([^\ ]+) ]]; then
                USER="${BASH_REMATCH[1]}"
            else
                # Extract username from journalctl sudo messages (format: "username : failure details")
                RAW_SUDO=$(journalctl _COMM=sudo -n3 -o cat | tail -1)
                if [[ "$RAW_SUDO" =~ ^([^\ :]+)\ : ]]; then
                    USER="${BASH_REMATCH[1]}"
                else
                    USER="unknown"
                fi
            fi

            # CRITICAL FIX: Make each sudo failure unique by including current timestamp
            EVENT_ID="sudo_fail_${USER}_${NOW}_$(echo "$LINE" | awk '{print $1"_"$2}')"

            # Reduced cooldown for sudo failures to catch rapid attempts
            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < 2 )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)
            CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
            CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
            MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"
            echo -e "${RED}[SUDO FAILURE]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"
            send_alert "❌ Sudo Failure" "$MSG" critical
        fi
    fi

    # --- SU ---
    if [[ "$LINE" =~ " su[" && "$LINE" =~ "session opened" ]]; then
        USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")
        EVENT_ID="su_success_${USER}_$(echo "$LINE" | awk '{print $1"_"$2}')"

        if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
            continue
        fi
        last_event[$EVENT_ID]=$NOW

        MSG="User: $USER | Time: $TS"
        echo -e "${GREEN}[SU SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "✅ su Login Success" "$MSG" critical

    elif [[ "$LINE" =~ " su[" && "$LINE" =~ "authentication failure" ]]; then
        # Extract both the source user (ruser) and target user (user) from su failure
        # Use more precise regex patterns with word boundaries
        if [[ "$LINE" =~ ruser=([^[:space:]]+) ]]; then
            SOURCE_USER="${BASH_REMATCH[1]}"
        elif [[ "$LINE" =~ logname=([^[:space:]]+) ]]; then
            SOURCE_USER="${BASH_REMATCH[1]}"
        else
            SOURCE_USER="unknown"
        fi

        if [[ "$LINE" =~ user=([^[:space:]]+)$ ]] || [[ "$LINE" =~ user=([^[:space:]]+)[[:space:]] ]]; then
            TARGET_USER="${BASH_REMATCH[1]}"
        else
            TARGET_USER="unknown"
        fi

        # Make each su failure unique
        EVENT_ID="su_fail_${SOURCE_USER}_${TARGET_USER}_${NOW}_$(echo "$LINE" | awk '{print $1"_"$2}')"

        if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < 2 )); then
            continue
        fi
        last_event[$EVENT_ID]=$NOW

        MSG="Source User: $SOURCE_USER | Target User: $TARGET_USER | Time: $TS"
        echo -e "${RED}[SU FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "❌ su Failure" "$MSG" critical
    fi
done
